// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPredictionMarket
 * @notice Interface for the PredictionMarket contract
 */
interface IPredictionMarket {
    enum Outcome {
        Yes, // 0
        No   // 1
    }

    enum MarketStatus {
        Active,    // 0
        Resolved,  // 1
        Cancelled  // 2
    }

    struct MarketInfo {
        uint256 id;
        string question;
        string category;
        address creator;
        uint256 yesPool;
        uint256 noPool;
        uint256 totalPool;
        uint256 endTime;
        MarketStatus status;
        Outcome winningOutcome;
        bool resolved;
    }

    /**
     * @notice Create a new market (called by MarketFactory)
     * @param question The prediction question
     * @param category The market category
     * @param creator The market creator address
     * @param endTime Unix timestamp when market closes
     * @param initialStake The initial stake amount
     * @param initialSide The side the creator is predicting (0 = Yes, 1 = No)
     * @return marketId The ID of the created market
     */
    function createMarket(
        string memory question,
        string memory category,
        address creator,
        uint256 endTime,
        uint256 initialStake,
        uint8 initialSide
    ) external returns (uint256 marketId);

    /**
     * @notice Get market information
     * @param marketId The market ID
     * @return MarketInfo struct with market details
     */
    function getMarketInfo(uint256 marketId) external view returns (MarketInfo memory);

    /**
     * @notice Get pool amount for a specific outcome
     * @param marketId The market ID
     * @param outcome The outcome (0 = Yes, 1 = No)
     * @return The pool amount
     */
    function poolAmounts(uint256 marketId, uint8 outcome) external view returns (uint256);

    /**
     * @notice Check if a market exists
     * @param marketId The market ID
     * @return True if market exists
     */
    function marketExists(uint256 marketId) external view returns (bool);

    /**
     * @notice Get total number of markets
     * @return The total market count
     */
    function getMarketCount() external view returns (uint256);
}

