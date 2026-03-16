// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {AbstractReactive} from "reactive-lib/abstract-base/AbstractReactive.sol";
import {PegGuardianTopics} from "../interfaces/IReactivePegGuardian.sol";

/// @title PegMonitorReactive
/// @notice Reactive Smart Contract that monitors RebalanceNeeded events from
///         StablecoinPegGuardianHook on origin chains and triggers cross-chain
///         protective callbacks on destination chains.
/// @dev Deployed on Reactive Network. Follows the Uniswap V2 Stop Order demo pattern.
///      Subscribes to RebalanceNeeded events and emits Callback to PegGuardianCallback.
contract PegMonitorReactive is IReactive, AbstractReactive {
    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a cross-chain callback is sent
    event CallbackSent(
        uint256 indexed originChainId,
        uint256 deviationBps,
        uint256 currentPrice
    );

    /// @notice Emitted when a protection confirmation is received
    event ProtectionConfirmed(uint256 indexed chainId);

    // =========================================================================
    // Errors
    // =========================================================================

    error AlreadyDone();

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Gas limit for cross-chain callback execution
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    // =========================================================================
    // State (ReactVM instance only)
    // =========================================================================

    /// @notice The chain ID of the origin chain where the hook is deployed
    uint256 public immutable ORIGIN_CHAIN_ID;

    /// @notice The chain ID of the destination chain for callbacks
    uint256 public immutable DESTINATION_CHAIN_ID;

    /// @notice Address of the hook contract on the origin chain
    address public immutable HOOK_ADDRESS;

    /// @notice Address of the PegGuardianCallback on the destination chain
    address public immutable CALLBACK_ADDRESS;

    /// @notice Number of callbacks sent
    uint256 public callbackCount;

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @notice Deploy and subscribe to RebalanceNeeded events from the hook
    /// @param _originChainId Chain ID where StablecoinPegGuardianHook is deployed
    /// @param _destinationChainId Chain ID where PegGuardianCallback is deployed
    /// @param _hookAddress Address of StablecoinPegGuardianHook on origin chain
    /// @param _callbackAddress Address of PegGuardianCallback on destination chain
    constructor(
        uint256 _originChainId,
        uint256 _destinationChainId,
        address _hookAddress,
        address _callbackAddress
    ) payable {
        ORIGIN_CHAIN_ID = _originChainId;
        DESTINATION_CHAIN_ID = _destinationChainId;
        HOOK_ADDRESS = _hookAddress;
        CALLBACK_ADDRESS = _callbackAddress;
    }

    // =========================================================================
    // Subscription
    // =========================================================================

    /// @notice Subscribes to RebalanceNeeded events from the hook on the origin chain
    /// @dev Must be called manually after deployment to avoid Forge simulation issues with `subscribe()`
    function subscribeToEvents() external rnOnly {
        service.subscribe(
            ORIGIN_CHAIN_ID,
            HOOK_ADDRESS,
            PegGuardianTopics.REBALANCE_NEEDED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    // =========================================================================
    // Reactive Logic (ReactVM only)
    // =========================================================================

    /// @notice Process incoming event logs from subscribed chains
    /// @dev Called by ReactVM when a subscribed event is detected.
    ///      Decodes RebalanceNeeded data and emits a Callback to trigger
    ///      PegGuardianCallback.handleRebalance() on the destination chain.
    /// @param log The intercepted log record
    function react(LogRecord calldata log) external vmOnly {
        // Verify the event comes from our hook
        if (log._contract != HOOK_ADDRESS) return;

        // Decode RebalanceNeeded event data: (uint256 deviationBps, uint256 currentPrice)
        (uint256 deviationBps, uint256 currentPrice) = abi.decode(
            log.data,
            (uint256, uint256)
        );

        // Encode the callback payload for PegGuardianCallback.handleRebalance()
        bytes memory payload = abi.encodeWithSignature(
            "handleRebalance(address,uint256,uint256)",
            address(0), // sender placeholder (filled by Reactive Network)
            currentPrice,
            deviationBps
        );

        callbackCount++;
        emit CallbackSent(log.chain_id, deviationBps, currentPrice);

        // Emit Callback event to trigger cross-chain execution
        emit Callback(
            DESTINATION_CHAIN_ID,
            CALLBACK_ADDRESS,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }
}
