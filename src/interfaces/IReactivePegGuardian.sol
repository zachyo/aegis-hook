// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReactivePegGuardian
/// @notice Shared constants for the Reactive cross-chain peg protection system
/// @dev Event topic hashes are precomputed via cast keccak
library PegGuardianTopics {
    /// @dev keccak256("RebalanceNeeded(bytes32,uint256,uint256)")
    uint256 internal constant REBALANCE_NEEDED_TOPIC_0 =
        0x6acac9bd2063073c2d2517e184707d3dd1992abcca939ac5200ccd785f9d9cff;

    /// @dev keccak256("PegProtectionExecuted(address,uint256,uint256)")
    uint256 internal constant PEG_PROTECTION_EXECUTED_TOPIC_0 =
        0xbc7f81a392cd547d7d5f6f166c266e57543a8485a1c8b256ceff54fe5f4cdc37;
}
