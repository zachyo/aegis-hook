// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AggregatorV3Interface
/// @notice Minimal Chainlink Price Feed interface
/// @dev See https://docs.chain.link/data-feeds/api-reference
interface AggregatorV3Interface {
    /// @notice Returns the number of decimals the price feed is denominated in
    function decimals() external view returns (uint8);

    /// @notice Returns a human-readable description of the feed
    function description() external view returns (string memory);

    /// @notice Returns the version of the feed
    function version() external view returns (uint256);

    /// @notice Returns round data for a specific round
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @notice Returns the latest round data
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
