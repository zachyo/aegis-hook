// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";

/// @title Gas Profiling Tests for StablecoinPegGuardianHook
/// @notice Measures gas usage per hook execution to verify <150k target
/// @dev Run with `forge test --match-path test/StablecoinPegGuardianHook.gas.t.sol -vvv`
///      or `forge test --gas-report` for full gas breakdown
contract StablecoinPegGuardianHookGasTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    StablecoinPegGuardianHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();

        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        address hookAddress = address(flags);
        deployCodeTo(
            "StablecoinPegGuardianHook.sol:StablecoinPegGuardianHook",
            abi.encode(manager, address(this)),
            hookAddress
        );
        hook = StablecoinPegGuardianHook(hookAddress);
    }

    // =========================================================================
    // Gas: Admin Operations (baseline measurements)
    // =========================================================================

    /// @notice Gas cost of updatePrice — typical admin operation
    function test_gas_updatePrice() public {
        uint256 gasBefore = gasleft();
        hook.updatePrice(0.995e18);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("updatePrice gas:", gasUsed);
        assertLt(gasUsed, 50_000, "updatePrice exceeds 50k gas");
    }

    /// @notice Gas cost of setPegPrice
    function test_gas_setPegPrice() public {
        uint256 gasBefore = gasleft();
        hook.setPegPrice(1.001e18);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("setPegPrice gas:", gasUsed);
        assertLt(gasUsed, 50_000, "setPegPrice exceeds 50k gas");
    }

    /// @notice Gas cost of pause
    function test_gas_pause() public {
        uint256 gasBefore = gasleft();
        hook.pause();
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("pause gas:", gasUsed);
        assertLt(gasUsed, 60_000, "pause exceeds 60k gas");
    }

    /// @notice Gas cost of unpause
    function test_gas_unpause() public {
        hook.pause();
        uint256 gasBefore = gasleft();
        hook.unpause();
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("unpause gas:", gasUsed);
        assertLt(gasUsed, 50_000, "unpause exceeds 50k gas");
    }

    // =========================================================================
    // Gas: Deviation Calculation
    // =========================================================================

    /// @notice Gas cost of getDeviationBps at peg (0 deviation)
    function test_gas_getDeviationBps_atPeg() public view {
        uint256 gasBefore = gasleft();
        hook.getDeviationBps();
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("getDeviationBps (at peg) gas:", gasUsed);
        assertLt(gasUsed, 15_000, "getDeviationBps exceeds 15k gas");
    }

    /// @notice Gas cost of getDeviationBps when deviated
    function test_gas_getDeviationBps_deviated() public {
        hook.updatePrice(0.99e18);
        uint256 gasBefore = gasleft();
        hook.getDeviationBps();
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("getDeviationBps (deviated) gas:", gasUsed);
        assertLt(gasUsed, 10_000, "getDeviationBps exceeds 10k gas");
    }

    // =========================================================================
    // Gas: Ownership Transfer
    // =========================================================================

    /// @notice Gas cost of full 2-step ownership transfer
    function test_gas_ownershipTransfer() public {
        address alice = makeAddr("alice");

        uint256 gasBefore = gasleft();
        hook.transferOwnership(alice);
        uint256 gasTransfer = gasBefore - gasleft();
        console2.log("transferOwnership gas:", gasTransfer);

        vm.prank(alice);
        gasBefore = gasleft();
        hook.acceptOwnership();
        uint256 gasAccept = gasBefore - gasleft();
        console2.log("acceptOwnership gas:", gasAccept);
        console2.log("Total ownership transfer gas:", gasTransfer + gasAccept);

        assertLt(
            gasTransfer + gasAccept,
            100_000,
            "Full ownership transfer exceeds 100k gas"
        );
    }

    // =========================================================================
    // Gas: Callback Price Update
    // =========================================================================

    /// @notice Gas cost of updatePriceFromCallback
    function test_gas_updatePriceFromCallback() public {
        address callbackAddr = makeAddr("callback");
        hook.setAuthorizedCallback(callbackAddr);

        vm.prank(callbackAddr);
        uint256 gasBefore = gasleft();
        hook.updatePriceFromCallback(0.995e18);
        uint256 gasUsed = gasBefore - gasleft();
        console2.log("updatePriceFromCallback gas:", gasUsed);
        assertLt(gasUsed, 50_000, "updatePriceFromCallback exceeds 50k gas");
    }
}
