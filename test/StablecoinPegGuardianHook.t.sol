// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";

contract StablecoinPegGuardianHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    StablecoinPegGuardianHook hook;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        deployFreshManagerAndRouters();

        // Compute the hook address flags matching our getHookPermissions()
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Deploy the hook to the correct flag-encoded address
        address hookAddress = address(flags);
        deployCodeTo(
            "StablecoinPegGuardianHook.sol:StablecoinPegGuardianHook", abi.encode(manager, address(this)), hookAddress
        );
        hook = StablecoinPegGuardianHook(hookAddress);
    }

    // =========================================================================
    // Hook Permissions
    // =========================================================================

    function test_hookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        assertTrue(perms.beforeAddLiquidity);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertFalse(perms.beforeInitialize);
        assertFalse(perms.afterInitialize);
        assertFalse(perms.afterAddLiquidity);
        assertFalse(perms.beforeRemoveLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
        assertFalse(perms.beforeDonate);
        assertFalse(perms.afterDonate);
    }

    function test_poolManager() public view {
        assertEq(address(hook.poolManager()), address(manager));
    }

    // =========================================================================
    // Initial State
    // =========================================================================

    function test_initialState() public view {
        assertEq(hook.pegPrice(), 1e18, "default peg should be 1e18");
        assertEq(hook.currentPrice(), 1e18, "default price should be 1e18");
        assertFalse(hook.paused(), "should not be paused initially");
        assertEq(hook.rebalanceCount(), 0, "rebalance count should start at 0");
    }

    // =========================================================================
    // Peg Deviation Calculation
    // =========================================================================

    function test_deviation_atPeg() public view {
        // currentPrice == pegPrice → 0 bps deviation
        assertEq(hook.getDeviationBps(), 0);
    }

    function test_deviation_halfPercent() public {
        // 0.5% deviation = 50 bps
        hook.updatePrice(0.995e18); // price below peg
        assertEq(hook.getDeviationBps(), 50);
    }

    function test_deviation_onePercent() public {
        // 1% deviation = 100 bps
        hook.updatePrice(1.01e18); // price above peg
        assertEq(hook.getDeviationBps(), 100);
    }

    function test_deviation_twoPercent() public {
        // 2% deviation = 200 bps (exceeds MAX_DEVIATION_BPS)
        hook.updatePrice(0.98e18);
        assertEq(hook.getDeviationBps(), 200);
    }

    function test_deviation_quarterPercent() public {
        // 0.25% deviation = 25 bps
        hook.updatePrice(0.9975e18);
        assertEq(hook.getDeviationBps(), 25);
    }

    // =========================================================================
    // Admin: Price Updates
    // =========================================================================

    function test_updatePrice() public {
        hook.updatePrice(0.99e18);
        assertEq(hook.currentPrice(), 0.99e18);
    }

    function test_updatePrice_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.PriceUpdated(1e18, 0.99e18);
        hook.updatePrice(0.99e18);
    }

    function test_updatePrice_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.updatePrice(0.99e18);
    }

    function test_updatePrice_revertsIfZero() public {
        vm.expectRevert(StablecoinPegGuardianHook.InvalidPrice.selector);
        hook.updatePrice(0);
    }

    // =========================================================================
    // Admin: Peg Price Updates
    // =========================================================================

    function test_setPegPrice() public {
        hook.setPegPrice(1.001e18);
        assertEq(hook.pegPrice(), 1.001e18);
    }

    function test_setPegPrice_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.PegPriceUpdated(1e18, 1.001e18);
        hook.setPegPrice(1.001e18);
    }

    function test_setPegPrice_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.setPegPrice(1.001e18);
    }

    function test_setPegPrice_revertsIfZero() public {
        vm.expectRevert(StablecoinPegGuardianHook.InvalidPrice.selector);
        hook.setPegPrice(0);
    }

    // =========================================================================
    // Admin: Pause / Unpause
    // =========================================================================

    function test_pause() public {
        hook.pause();
        assertTrue(hook.paused());
    }

    function test_pause_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.Paused(address(this));
        hook.pause();
    }

    function test_unpause() public {
        hook.pause();
        hook.unpause();
        assertFalse(hook.paused());
    }

    function test_unpause_emitsEvent() public {
        hook.pause();
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.Unpaused(address(this));
        hook.unpause();
    }

    function test_pause_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.pause();
    }

    function test_unpause_revertsIfNotOwner() public {
        hook.pause();
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.unpause();
    }

    // =========================================================================
    // Admin: 2-Step Ownership Transfer
    // =========================================================================

    function test_transferOwnership() public {
        hook.transferOwnership(alice);
        assertEq(hook.pendingOwner(), alice);
    }

    function test_transferOwnership_emitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit StablecoinPegGuardianHook.OwnershipTransferStarted(alice);
        hook.transferOwnership(alice);
    }

    function test_transferOwnership_revertsIfZeroAddress() public {
        vm.expectRevert(StablecoinPegGuardianHook.ZeroAddress.selector);
        hook.transferOwnership(address(0));
    }

    function test_transferOwnership_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.transferOwnership(bob);
    }

    function test_acceptOwnership() public {
        hook.transferOwnership(alice);

        vm.prank(alice);
        hook.acceptOwnership();

        assertEq(hook.owner(), alice);
        assertEq(hook.pendingOwner(), address(0));
    }

    function test_acceptOwnership_emitsEvent() public {
        hook.transferOwnership(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit StablecoinPegGuardianHook.OwnershipTransferred(address(this), alice);
        hook.acceptOwnership();
    }

    function test_acceptOwnership_revertsIfNotPendingOwner() public {
        hook.transferOwnership(alice);

        vm.prank(bob);
        vm.expectRevert(StablecoinPegGuardianHook.NotPendingOwner.selector);
        hook.acceptOwnership();
    }

    function test_newOwnerCanCallAdminFunctions() public {
        hook.transferOwnership(alice);
        vm.prank(alice);
        hook.acceptOwnership();

        // Alice should now be able to update price
        vm.prank(alice);
        hook.updatePrice(0.99e18);
        assertEq(hook.currentPrice(), 0.99e18);
    }

    function test_oldOwnerCannotCallAfterTransfer() public {
        hook.transferOwnership(alice);
        vm.prank(alice);
        hook.acceptOwnership();

        // Old owner (this contract) should be rejected
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.updatePrice(0.99e18);
    }
}
