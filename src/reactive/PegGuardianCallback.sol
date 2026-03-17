// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "reactive-lib/abstract-base/AbstractCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title PegGuardianCallback
/// @notice Destination chain contract that receives cross-chain callbacks from
///         PegMonitorReactive and executes protective price updates on the
///         StablecoinPegGuardianHook.
/// @dev Deployed on each destination chain (Base, Arbitrum, Optimism, etc.)
///      Follows the Uniswap V2 Stop Order demo pattern using AbstractCallback.
contract PegGuardianCallback is AbstractCallback {
    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a cross-chain peg protection action is executed
    /// @param hook Address of the hook that was updated
    /// @param newPrice The new price set on the hook
    /// @param deviationBps The peg deviation that triggered the protection
    event PegProtectionExecuted(address indexed hook, uint256 newPrice, uint256 deviationBps);

    // =========================================================================
    // Errors
    // =========================================================================

    error ZeroAddress();
    error CallFailed();

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Address of the StablecoinPegGuardianHook on this chain
    address public immutable HOOK_ADDRESS;
    address public immutable SWAP_ROUTER;
    PoolKey public poolKey;

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @notice Deploy the callback contract
    /// @param _callbackSender Address authorized to send callbacks (Reactive Network system)
    /// @param _hookAddress Address of StablecoinPegGuardianHook on this destination chain
    /// @param _swapRouter Address of the PoolSwapTest router to execute protective swaps
    /// @param _poolKey The Uniswap v4 pool key to protect
    constructor(
        address _callbackSender, 
        address _hookAddress,
        address _swapRouter,
        PoolKey memory _poolKey
    ) payable AbstractCallback(_callbackSender) {
        if (_hookAddress == address(0) || _swapRouter == address(0)) revert ZeroAddress();
        HOOK_ADDRESS = _hookAddress;
        SWAP_ROUTER = _swapRouter;
        poolKey = _poolKey;

        // Infinite approve the router
        IERC20(Currency.unwrap(_poolKey.currency0)).approve(_swapRouter, type(uint256).max);
        IERC20(Currency.unwrap(_poolKey.currency1)).approve(_swapRouter, type(uint256).max);
    }

    // =========================================================================
    // Callback Handler
    // =========================================================================

    /// @notice Handle a cross-chain rebalance callback from PegMonitorReactive
    /// @dev Called by the Reactive Network when PegMonitorReactive emits a Callback event.
    ///      Updates the hook's price via updatePriceFromCallback().
    /// @param newPrice The current price detected on the origin chain
    /// @param deviationBps The peg deviation in basis points
    function handleRebalance(
        address,
        /* sender — unused, filled by Reactive Network */
        uint256 newPrice,
        uint256 deviationBps
    )
        external
        authorizedSenderOnly
    {
        // 1. Update the oracle price on the hook first
        (bool success,) = HOOK_ADDRESS.call(abi.encodeWithSignature("updatePriceFromCallback(uint256)", newPrice));
        if (!success) revert CallFailed();

        // 2. Execute a protective swap against the pool
        // If price fell, we assume the stablecoin lost value. If price rose, the stablecoin gained value.
        // For demonstration, we simply execute a small swap to rebalance.
        // Assuming Peg is 1e18, if newPrice < 1e18, we swap to buy the stablecoin.
        
        bool zeroForOne = newPrice < 1e18; // simplistic logic to determine swap direction
        // Swap 100 units of the stronger token to buy back the depegged token
        uint256 swapAmount = 100;

        PoolSwapTest(SWAP_ROUTER).swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                // casting to 'int256' is safe because swapAmount is smaller than type(int256).max
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            new bytes(0)
        );

        emit PegProtectionExecuted(HOOK_ADDRESS, newPrice, deviationBps);
    }
}
