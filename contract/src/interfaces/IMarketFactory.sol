// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IMarketFactory
 * @notice Interface for the MarketFactory contract
 */
interface IMarketFactory {
    /**
     * @notice Create a new prediction market
     * @param question The prediction question
     * @param category The market category
     * @param endTime Unix timestamp when market closes
     * @param initialStake The amount the creator must stake
     * @param initialSide The side the creator is predicting (0 = Yes, 1 = No)
     * @return marketId The ID of the created market
     */
    function createMarket(
        string memory question,
        string memory category,
        uint256 endTime,
        uint256 initialStake,
        uint8 initialSide
    ) external returns (uint256 marketId);

    /**
     * @notice Get total number of markets
     * @return The total market count
     */
    function getMarketCount() external view returns (uint256);

    /**
     * @notice Get market ID by index
     * @param index The index (0-based)
     * @return The market ID (1-based)
     */
    function getMarketId(uint256 index) external view returns (uint256);

    /**
     * @notice Get market address (always returns the single PredictionMarket contract)
     * @param marketId The market ID (unused, kept for interface compatibility)
     * @return The PredictionMarket contract address
     */
    function getMarketAddress(uint256 marketId) external view returns (address);

    /**
     * @notice Get all market IDs
     * @return Array of all market IDs
     */
    function getAllMarketIds() external view returns (uint256[] memory);

    /**
     * @notice Check if a market exists
     * @param marketId The market ID
     * @return True if market exists
     */
    function marketExists(uint256 marketId) external view returns (bool);
}

