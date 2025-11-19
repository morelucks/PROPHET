// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPredictionMarket.sol";
import "../interfaces/IMarketFactory.sol";

/**
 * @title MarketFactory
 * @notice Factory contract for creating prediction markets
 * @dev Now acts as a wrapper around a single PredictionMarket contract
 *      All markets are stored in one contract, identified by marketId
 */
contract MarketFactory is Ownable, ReentrancyGuard, IMarketFactory {
    using SafeERC20 for IERC20;

    /// @notice The payment token (cUSD)
    IERC20 public immutable paymentToken;

    /// @notice The single PredictionMarket contract
    IPredictionMarket public immutable predictionMarket;

    /// @notice The Oracle contract address
    address public oracle;

    /// @notice The ReputationSystem contract address
    address public immutable reputationSystem;

    /// @notice Creation fee in payment token units
    uint256 public creationFee;

    /// @notice Array of all market IDs (for getAllMarketIds)
    uint256[] private allMarketIds;

    /// @notice Mapping from market ID to index in allMarketIds array
    mapping(uint256 => uint256) private marketIdToIndex;

    /// @notice Mapping to track if a market ID exists
    mapping(uint256 => bool) private marketIdExists;

    /// @notice Event emitted when a new market is created
    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string question,
        string category,
        uint256 endTime
    );

    /// @notice Event emitted when creation fee is updated
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    /// @notice Event emitted when oracle is updated
    event OracleUpdated(address oldOracle, address newOracle);

    /**
     * @notice Constructor
     * @param _paymentToken The payment token address (cUSD)
     * @param _predictionMarket The PredictionMarket contract address
     * @param _oracle The Oracle contract address
     * @param _reputationSystem The ReputationSystem contract address
     * @param _owner The owner address
     */
    constructor(
        address _paymentToken,
        address _predictionMarket,
        address _oracle,
        address _reputationSystem,
        address _owner
    ) Ownable(_owner) {
        require(_paymentToken != address(0), "MarketFactory: invalid payment token");
        require(_predictionMarket != address(0), "MarketFactory: invalid prediction market");
        require(_oracle != address(0), "MarketFactory: invalid oracle");
        require(_reputationSystem != address(0), "MarketFactory: invalid reputation system");

        paymentToken = IERC20(_paymentToken);
        predictionMarket = IPredictionMarket(_predictionMarket);
        oracle = _oracle;
        reputationSystem = _reputationSystem;
    }

    /**
     * @notice Create a new prediction market
     * @param question The prediction question
     * @param category The market category
     * @param endTime Unix timestamp when market closes
     * @param initialStake The amount the creator must stake (put your money where your mouth is)
     * @param initialSide The side the creator is predicting (0 = Yes, 1 = No)
     * @return marketId The ID of the created market
     */
    function createMarket(
        string memory question,
        string memory category,
        uint256 endTime,
        uint256 initialStake,
        uint8 initialSide
    ) external nonReentrant returns (uint256 marketId) {
        require(bytes(question).length > 0, "MarketFactory: empty question");
        require(bytes(category).length > 0, "MarketFactory: empty category");
        require(endTime > block.timestamp, "MarketFactory: invalid end time");
        require(
            endTime <= block.timestamp + 365 days,
            "MarketFactory: end time too far"
        );
        require(initialStake > 0, "MarketFactory: initial stake required");

        // Collect creation fee if set
        if (creationFee > 0) {
            paymentToken.safeTransferFrom(msg.sender, address(this), creationFee);
        }

        // Transfer initial stake from creator
        paymentToken.safeTransferFrom(msg.sender, address(predictionMarket), initialStake);

        // Create market in PredictionMarket contract
        marketId = predictionMarket.createMarket(
            question,
            category,
            msg.sender,
            endTime,
            initialStake,
            initialSide
        );

        // Track market ID
        if (!marketIdExists[marketId]) {
            marketIdToIndex[marketId] = allMarketIds.length;
            allMarketIds.push(marketId);
            marketIdExists[marketId] = true;
        }

        emit MarketCreated(marketId, msg.sender, question, category, endTime);
    }

    /**
     * @notice Get total number of markets
     * @return The total market count
     */
    function getMarketCount() external view returns (uint256) {
        return predictionMarket.getMarketCount();
    }

    /**
     * @notice Get market ID by index
     * @param index The index of the market (0-based)
     * @return The market ID (1-based)
     */
    function getMarketId(uint256 index) external view returns (uint256) {
        uint256 count = predictionMarket.getMarketCount();
        require(index < count, "MarketFactory: index out of bounds");
        // Market IDs are sequential starting from 1
        return index + 1;
    }

    /**
     * @notice Get market address (always returns the single PredictionMarket contract)
     * @param marketId The market ID (unused, kept for interface compatibility)
     * @return The PredictionMarket contract address
     */
    function getMarketAddress(uint256 marketId) external view returns (address) {
        // Always return the single PredictionMarket contract address
        // marketId is unused but kept for interface compatibility
        marketId; // Silence unused parameter warning
        return address(predictionMarket);
    }

    /**
     * @notice Get all market IDs
     * @return Array of all market IDs
     */
    function getAllMarketIds() external view returns (uint256[] memory) {
        uint256 count = predictionMarket.getMarketCount();
        uint256[] memory ids = new uint256[](count);
        
        // Market IDs are sequential starting from 1
        for (uint256 i = 0; i < count; i++) {
            ids[i] = i + 1;
        }
        
        return ids;
    }

    /**
     * @notice Check if a market exists
     * @param marketId The ID of the market
     * @return True if market exists
     */
    function marketExists(uint256 marketId) external view returns (bool) {
        return predictionMarket.marketExists(marketId);
    }

    /**
     * @notice Set the creation fee (owner only)
     * @param _creationFee New creation fee amount
     */
    function setCreationFee(uint256 _creationFee) external onlyOwner {
        uint256 oldFee = creationFee;
        creationFee = _creationFee;
        emit CreationFeeUpdated(oldFee, _creationFee);
    }

    /**
     * @notice Set the oracle address (owner only, for initialization)
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "MarketFactory: invalid oracle");
        address oldOracle = oracle;
        oracle = _oracle;
        emit OracleUpdated(oldOracle, _oracle);
    }

    /**
     * @notice Withdraw collected fees (owner only)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = paymentToken.balanceOf(address(this));
        if (balance > 0) {
            paymentToken.safeTransfer(owner(), balance);
        }
    }
}

