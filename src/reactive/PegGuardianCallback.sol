// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "reactive-lib/abstract-base/AbstractCallback.sol";

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

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @notice Deploy the callback contract
    /// @param _callbackSender Address authorized to send callbacks (Reactive Network system)
    /// @param _hookAddress Address of StablecoinPegGuardianHook on this destination chain
    constructor(address _callbackSender, address _hookAddress) payable AbstractCallback(_callbackSender) {
        if (_hookAddress == address(0)) revert ZeroAddress();
        HOOK_ADDRESS = _hookAddress;
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
        // Call updatePriceFromCallback on the hook
        // This function exists on the hook specifically for authorized callback contracts
        (bool success,) = HOOK_ADDRESS.call(abi.encodeWithSignature("updatePriceFromCallback(uint256)", newPrice));
        if (!success) revert CallFailed();

        emit PegProtectionExecuted(HOOK_ADDRESS, newPrice, deviationBps);
    }
}
