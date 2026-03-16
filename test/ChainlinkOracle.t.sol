// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";

/// @title Mock Chainlink Price Feed for testing
contract MockChainlinkFeed {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
        _roundId = 1;
    }

    function setAnswer(int256 answer_, uint256 updatedAt_) external {
        _answer = answer_;
        _updatedAt = updatedAt_;
        _roundId++;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "USDC / USD";
    }

    function version() external pure returns (uint256) {
        return 4;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}

/// @title Chainlink Oracle Integration Tests
contract ChainlinkOracleTest is Test, Deployers {
    StablecoinPegGuardianHook hook;
    MockChainlinkFeed mockFeed;

    function setUp() public {
        deployFreshManagerAndRouters();

        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        address hookAddress = address(flags);
        deployCodeTo(
            "StablecoinPegGuardianHook.sol:StablecoinPegGuardianHook", abi.encode(manager, address(this)), hookAddress
        );
        hook = StablecoinPegGuardianHook(hookAddress);

        // Deploy mock Chainlink feed with 8 decimals (standard for USD pairs)
        mockFeed = new MockChainlinkFeed(8);

        // Warp to a realistic block timestamp to avoid underflow in staleness checks
        vm.warp(1_700_000_000); // ~Nov 2023
    }

    // =========================================================================
    // setChainlinkOracle
    // =========================================================================

    function test_setChainlinkOracle() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);
        assertEq(address(hook.chainlinkOracle()), address(mockFeed));
        assertEq(hook.oracleStalenessThreshold(), 3600);
        assertEq(hook.oracleDecimals(), 8);
    }

    function test_setChainlinkOracle_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.ChainlinkOracleUpdated(address(mockFeed), 3600);
        hook.setChainlinkOracle(address(mockFeed), 3600);
    }

    function test_setChainlinkOracle_revertsIfNotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.setChainlinkOracle(address(mockFeed), 3600);
    }

    function test_setChainlinkOracle_revertsIfZeroAddress() public {
        vm.expectRevert(StablecoinPegGuardianHook.ZeroAddress.selector);
        hook.setChainlinkOracle(address(0), 3600);
    }

    // =========================================================================
    // updatePriceFromOracle
    // =========================================================================

    function test_updatePriceFromOracle() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);

        // Simulate Chainlink returning $0.995 (8 decimals = 99500000)
        mockFeed.setAnswer(99_500_000, block.timestamp);

        hook.updatePriceFromOracle();

        // Should normalize to 18 decimals: 99500000 * 1e10 = 0.995e18
        assertEq(hook.currentPrice(), 0.995e18);
    }

    function test_updatePriceFromOracle_exactPeg() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);

        // $1.00 exactly
        mockFeed.setAnswer(100_000_000, block.timestamp);
        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 1e18);
    }

    function test_updatePriceFromOracle_abovePeg() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);

        // $1.005
        mockFeed.setAnswer(100_500_000, block.timestamp);
        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 1.005e18);
    }

    function test_updatePriceFromOracle_emitsEvent() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);
        mockFeed.setAnswer(99_500_000, block.timestamp);

        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.OraclePriceUpdated(
            1e18, // old price (initial)
            0.995e18, // new price
            2 // roundId (constructor sets 1, setAnswer increments to 2)
        );
        hook.updatePriceFromOracle();
    }

    function test_updatePriceFromOracle_isPermissionless() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);
        mockFeed.setAnswer(99_500_000, block.timestamp);

        // Anyone can call updatePriceFromOracle
        address alice = makeAddr("alice");
        vm.prank(alice);
        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 0.995e18);
    }

    // =========================================================================
    // Oracle validation
    // =========================================================================

    function test_updatePriceFromOracle_revertsIfOracleNotSet() public {
        vm.expectRevert(StablecoinPegGuardianHook.OracleNotSet.selector);
        hook.updatePriceFromOracle();
    }

    function test_updatePriceFromOracle_revertsIfPriceNegative() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);
        mockFeed.setAnswer(-1, block.timestamp);

        vm.expectRevert(StablecoinPegGuardianHook.InvalidOraclePrice.selector);
        hook.updatePriceFromOracle();
    }

    function test_updatePriceFromOracle_revertsIfPriceZero() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);
        mockFeed.setAnswer(0, block.timestamp);

        vm.expectRevert(StablecoinPegGuardianHook.InvalidOraclePrice.selector);
        hook.updatePriceFromOracle();
    }

    function test_updatePriceFromOracle_revertsIfStale() public {
        hook.setChainlinkOracle(address(mockFeed), 3600); // 1 hour staleness

        // Set answer that's 2 hours old
        mockFeed.setAnswer(99_500_000, block.timestamp - 7200);

        vm.expectRevert(StablecoinPegGuardianHook.StaleOracleData.selector);
        hook.updatePriceFromOracle();
    }

    function test_updatePriceFromOracle_allowsIfWithinStaleness() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);

        // Set answer that's 30 minutes old (within 1 hour threshold)
        mockFeed.setAnswer(99_500_000, block.timestamp - 1800);

        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 0.995e18);
    }

    function test_updatePriceFromOracle_zeroStalenessSkipsCheck() public {
        // Setting staleness to 0 means "no staleness check"
        hook.setChainlinkOracle(address(mockFeed), 0);

        // Even with very old data, no revert
        mockFeed.setAnswer(99_500_000, block.timestamp - 100_000);

        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 0.995e18);
    }

    // =========================================================================
    // Decimal normalization
    // =========================================================================

    function test_updatePriceFromOracle_18decimals() public {
        // Some feeds use 18 decimals
        MockChainlinkFeed feed18 = new MockChainlinkFeed(18);
        hook.setChainlinkOracle(address(feed18), 3600);

        feed18.setAnswer(int256(0.995e18), block.timestamp);
        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 0.995e18);
    }

    function test_updatePriceFromOracle_6decimals() public {
        // Some feeds use 6 decimals
        MockChainlinkFeed feed6 = new MockChainlinkFeed(6);
        hook.setChainlinkOracle(address(feed6), 3600);

        // $0.995 with 6 decimals = 995000
        feed6.setAnswer(995_000, block.timestamp);
        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 0.995e18);
    }

    // =========================================================================
    // Admin updatePrice still works alongside oracle
    // =========================================================================

    function test_adminUpdateOverridesOracle() public {
        hook.setChainlinkOracle(address(mockFeed), 3600);
        mockFeed.setAnswer(99_500_000, block.timestamp);
        hook.updatePriceFromOracle();
        assertEq(hook.currentPrice(), 0.995e18);

        // Admin can still override
        hook.updatePrice(1e18);
        assertEq(hook.currentPrice(), 1e18);
    }
}
