// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";
import {PegGuardianCallback} from "../src/reactive/PegGuardianCallback.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract MockRouter {
    function swap(PoolKey memory, SwapParams memory, PoolSwapTest.TestSettings memory, bytes memory) external payable returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }
}

/// @title PegGuardianCallbackTest
/// @notice Tests for PegGuardianCallback + hook callback integration
contract PegGuardianCallbackTest is Test, Deployers {
    StablecoinPegGuardianHook hook;
    PegGuardianCallback callback;

    address alice = makeAddr("alice");
    address reactiveSystem = makeAddr("reactiveSystem");

    function setUp() public {
        deployFreshManagerAndRouters();

        // Deploy hook to flag-encoded address
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        address hookAddress = address(flags);
        deployCodeTo(
            "StablecoinPegGuardianHook.sol:StablecoinPegGuardianHook", abi.encode(manager, address(this)), hookAddress
        );
        hook = StablecoinPegGuardianHook(hookAddress);

        // Deploy callback contract — reactiveSystem is the authorized sender
        MockERC20 token0 = new MockERC20("Token0", "T0", 18);
        MockERC20 token1 = new MockERC20("Token1", "T1", 18);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: hook
        });
        
        MockRouter mockRouter = new MockRouter();
        callback = new PegGuardianCallback(reactiveSystem, hookAddress, address(mockRouter), poolKey);

        // Authorize the callback contract on the hook
        hook.setAuthorizedCallback(address(callback));
    }

    // =========================================================================
    // Integration: Callback → Hook price update
    // =========================================================================

    function test_callbackUpdatesHookPrice() public {
        // Simulate the Reactive system calling handleRebalance
        vm.prank(reactiveSystem);
        callback.handleRebalance(address(0), 0.995e18, 50);

        // Hook price should be updated
        assertEq(hook.currentPrice(), 0.995e18);
    }

    function test_callbackEmitsPegProtectionExecuted() public {
        vm.prank(reactiveSystem);
        vm.expectEmit(true, false, false, true);
        emit PegGuardianCallback.PegProtectionExecuted(address(hook), 0.99e18, 100);
        callback.handleRebalance(address(0), 0.99e18, 100);
    }

    function test_callbackEmitsCallbackPriceUpdatedOnHook() public {
        vm.prank(reactiveSystem);
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.CallbackPriceUpdated(1e18, 0.995e18, address(callback));
        callback.handleRebalance(address(0), 0.995e18, 50);
    }

    // =========================================================================
    // Authorization
    // =========================================================================

    function test_callbackRevertsIfNotAuthorizedSender() public {
        // Alice is not the authorized Reactive system sender
        vm.prank(alice);
        vm.expectRevert();
        callback.handleRebalance(address(0), 0.99e18, 100);
    }

    function test_hookRevertsIfNotAuthorizedCallback() public {
        // Direct call to updatePriceFromCallback from non-callback address
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotAuthorizedCallback.selector);
        hook.updatePriceFromCallback(0.99e18);
    }

    function test_hookRevertsCallbackUpdateWithZeroPrice() public {
        // Even authorized callback can't set price to 0
        vm.prank(reactiveSystem);
        vm.expectRevert(PegGuardianCallback.CallFailed.selector);
        callback.handleRebalance(address(0), 0, 50);
    }

    // =========================================================================
    // Admin: setAuthorizedCallback
    // =========================================================================

    function test_setAuthorizedCallback() public {
        address newCallback = makeAddr("newCallback");
        hook.setAuthorizedCallback(newCallback);
        assertEq(hook.authorizedCallback(), newCallback);
    }

    function test_setAuthorizedCallbackEmitsEvent() public {
        address newCallback = makeAddr("newCallback");
        vm.expectEmit(false, false, false, true);
        emit StablecoinPegGuardianHook.AuthorizedCallbackUpdated(address(callback), newCallback);
        hook.setAuthorizedCallback(newCallback);
    }

    function test_setAuthorizedCallbackRevertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(StablecoinPegGuardianHook.NotOwner.selector);
        hook.setAuthorizedCallback(alice);
    }

    // =========================================================================
    // Multiple callback calls
    // =========================================================================

    function test_multipleCallbackUpdates() public {
        vm.startPrank(reactiveSystem);
        callback.handleRebalance(address(0), 0.995e18, 50);
        assertEq(hook.currentPrice(), 0.995e18);

        callback.handleRebalance(address(0), 0.99e18, 100);
        assertEq(hook.currentPrice(), 0.99e18);

        callback.handleRebalance(address(0), 1.001e18, 10);
        assertEq(hook.currentPrice(), 1.001e18);
        vm.stopPrank();
    }
}
