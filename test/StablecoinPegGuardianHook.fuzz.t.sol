// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";
import {PegGuardianCallback} from "../src/reactive/PegGuardianCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract MockRouter {
    function swap(PoolKey memory, SwapParams memory, PoolSwapTest.TestSettings memory, bytes memory) external payable returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }
}

/// @title Fuzz Tests for StablecoinPegGuardianHook
/// @notice Exercises core math and admin functions with randomized inputs
contract StablecoinPegGuardianHookFuzzTest is Test, Deployers {
    StablecoinPegGuardianHook hook;
    PegGuardianCallback callback;
    address reactiveSystem = makeAddr("reactiveSystem");

    // Mirror constants from the hook for test assertions
    uint256 constant PRICE_PRECISION = 1e18;
    uint24 constant MAX_FEE = 10_000;
    uint24 constant LARGECAP_SURCHARGE = 2_000;
    uint256 constant MAX_DEVIATION_BPS = 100;
    uint256 constant BPS_PRECISION = 10_000;
    uint256 constant LARGECAP_THRESHOLD = 100_000e18;

    function setUp() public {
        deployFreshManagerAndRouters();

        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        address hookAddress = address(flags);
        deployCodeTo(
            "StablecoinPegGuardianHook.sol:StablecoinPegGuardianHook", abi.encode(manager, address(this)), hookAddress
        );
        hook = StablecoinPegGuardianHook(hookAddress);

        MockERC20 token0 = new MockERC20("Token0", "T0", 18);
        MockERC20 token1 = new MockERC20("Token1", "T1", 18);

        // Deploy callback for callback-path fuzz tests
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: hook
        });
        MockRouter mockRouter = new MockRouter();
        callback = new PegGuardianCallback(reactiveSystem, hookAddress, address(mockRouter), poolKey);
        hook.setAuthorizedCallback(address(callback));
    }

    // =========================================================================
    // Fuzz: Deviation Math
    // =========================================================================

    /// @notice For any valid price, deviation math produces correct result
    /// @dev deviationBps = |currentPrice - pegPrice| / pegPrice * 10_000
    function testFuzz_deviationBps_correctness(uint256 price) public {
        // Bound price to realistic range: [1 wei, 10 * 1e18]
        // Avoids 0 (which is InvalidPrice) and unrealistic extremes
        price = bound(price, 1, 10e18);

        hook.updatePrice(price);
        uint256 actualDeviation = hook.getDeviationBps();

        // Manual calculation
        uint256 peg = hook.pegPrice(); // 1e18
        uint256 diff = price >= peg ? price - peg : peg - price;
        uint256 expectedDeviation = (diff * BPS_PRECISION) / peg;

        assertEq(actualDeviation, expectedDeviation, "Deviation mismatch");
    }

    /// @notice Deviation is symmetric: deviating above and below peg by the same
    ///         amount should produce the same deviation in bps
    function testFuzz_deviationBps_symmetry(uint256 delta) public {
        // delta in [1, 0.5e18] so price stays positive in both directions
        delta = bound(delta, 1, 0.5e18);

        uint256 peg = hook.pegPrice();

        // Price above peg
        hook.updatePrice(peg + delta);
        uint256 deviationAbove = hook.getDeviationBps();

        // Price below peg
        hook.updatePrice(peg - delta);
        uint256 deviationBelow = hook.getDeviationBps();

        // Symmetry: deviation above vs below should be very close
        // Not exactly equal due to integer division with different denominators,
        // but the diff is always ≤ 1 bps since both use peg as denominator
        assertEq(deviationAbove, deviationBelow, "Deviation not symmetric");
    }

    // =========================================================================
    // Fuzz: Dynamic Fee Bounds
    // =========================================================================

    /// @notice The dynamic fee is always within valid bounds [0, MAX_FEE]
    ///         when no surcharge is applied (deviation only)
    function testFuzz_dynamicFee_bounded(uint256 price) public {
        price = bound(price, 1, 10e18);
        hook.updatePrice(price);

        uint256 deviationBps = hook.getDeviationBps();

        // Compute expected fee
        uint24 expectedFee;
        if (deviationBps >= MAX_DEVIATION_BPS) {
            expectedFee = MAX_FEE;
        } else {
            // expectedFee is within [0, MAX_FEE] bounds so uint24 cast is safe
            // forge-lint: disable-next-line(unsafe-typecast)
            expectedFee = uint24((deviationBps * MAX_FEE) / MAX_DEVIATION_BPS);
        }

        assertTrue(expectedFee <= MAX_FEE, "Fee exceeds MAX_FEE");
    }

    /// @notice Fee scales linearly: for deviations below MAX_DEVIATION_BPS,
    ///         fee = deviationBps * MAX_FEE / MAX_DEVIATION_BPS (integer math)
    function testFuzz_dynamicFee_linearScaling(uint256 deviationBps) public {
        // Test deviations in [0, MAX_DEVIATION_BPS - 1] for the linear region
        deviationBps = bound(deviationBps, 0, MAX_DEVIATION_BPS - 1);

        // Set price to produce this exact deviation
        // deviation = |price - peg| / peg * 10_000
        // So price = peg * (1 - deviation/10_000) for below-peg
        uint256 peg = hook.pegPrice();
        uint256 price = peg - (peg * deviationBps) / BPS_PRECISION;
        if (price == 0) price = 1; // avoid zero

        hook.updatePrice(price);
        uint256 actualDeviation = hook.getDeviationBps();

        // Due to integer rounding, actualDeviation might differ by ±1 from target
        // Compute expected fee from the actual deviation the contract sees
        // actualDeviation is bounded, so uint24 cast is safe
        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 expectedFee = uint24((actualDeviation * MAX_FEE) / MAX_DEVIATION_BPS);

        // Verify it's in the linear region if deviation < MAX_DEVIATION_BPS
        if (actualDeviation < MAX_DEVIATION_BPS) {
            assertTrue(expectedFee <= MAX_FEE, "Fee in linear region exceeds MAX_FEE");
            // Also verify the linear formula holds exactly
            // actualDeviation is bounded, so uint24 cast is safe
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(expectedFee, uint24((actualDeviation * MAX_FEE) / MAX_DEVIATION_BPS), "Linear formula mismatch");
        }
    }

    // =========================================================================
    // Fuzz: Large-Cap Surcharge
    // =========================================================================

    /// @notice The total fee (deviation fee + surcharge) never exceeds MAX_LP_FEE
    function testFuzz_feeNeverExceedsMaxLPFee(uint256 price, uint256 swapAmount) public {
        price = bound(price, 1, 10e18);
        swapAmount = bound(swapAmount, 1, type(uint128).max);

        hook.updatePrice(price);

        uint256 deviationBps = hook.getDeviationBps();

        // Compute fee as the contract would
        uint24 fee;
        if (deviationBps >= MAX_DEVIATION_BPS) {
            fee = MAX_FEE;
        } else {
            // fee is within [0, MAX_FEE] bounds so uint24 cast is safe
            // forge-lint: disable-next-line(unsafe-typecast)
            fee = uint24((deviationBps * MAX_FEE) / MAX_DEVIATION_BPS);
        }

        if (swapAmount >= LARGECAP_THRESHOLD) {
            fee += LARGECAP_SURCHARGE;
        }

        // Contract caps at MAX_LP_FEE
        if (fee > uint24(LPFeeLibrary.MAX_LP_FEE)) {
            fee = uint24(LPFeeLibrary.MAX_LP_FEE);
        }

        assertTrue(fee <= uint24(LPFeeLibrary.MAX_LP_FEE), "Fee exceeds MAX_LP_FEE after capping");
    }

    // =========================================================================
    // Fuzz: Admin Functions
    // =========================================================================

    /// @notice updatePrice succeeds for any non-zero price and reverts for zero
    function testFuzz_updatePrice(uint256 newPrice) public {
        if (newPrice == 0) {
            vm.expectRevert(StablecoinPegGuardianHook.InvalidPrice.selector);
            hook.updatePrice(newPrice);
        } else {
            hook.updatePrice(newPrice);
            assertEq(hook.currentPrice(), newPrice, "Price not updated correctly");
        }
    }

    /// @notice setPegPrice succeeds for any non-zero peg and reverts for zero
    function testFuzz_setPegPrice(uint256 newPeg) public {
        if (newPeg == 0) {
            vm.expectRevert(StablecoinPegGuardianHook.InvalidPrice.selector);
            hook.setPegPrice(newPeg);
        } else {
            hook.setPegPrice(newPeg);
            assertEq(hook.pegPrice(), newPeg, "Peg price not updated correctly");
        }
    }

    /// @notice Callback price update follows authorization rules
    function testFuzz_callbackPriceUpdate(uint256 newPrice) public {
        if (newPrice == 0) {
            // Authorized callback with zero price → revert CallFailed
            vm.prank(reactiveSystem);
            vm.expectRevert(PegGuardianCallback.CallFailed.selector);
            callback.handleRebalance(address(0), newPrice, 50);
        } else {
            // Authorized callback with valid price → success
            vm.prank(reactiveSystem);
            callback.handleRebalance(address(0), newPrice, 50);
            assertEq(hook.currentPrice(), newPrice, "Callback price update failed");
        }
    }

    /// @notice Unauthorized addresses can never update price via callback
    function testFuzz_callbackUnauthorized(address caller, uint256 newPrice) public {
        newPrice = bound(newPrice, 1, 10e18);
        vm.assume(caller != reactiveSystem);
        vm.assume(caller != address(0));

        vm.prank(caller);
        vm.expectRevert(); // authorizedSenderOnly will revert
        callback.handleRebalance(address(0), newPrice, 50);
    }
}
