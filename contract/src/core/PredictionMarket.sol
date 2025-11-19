// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPredictionMarket.sol";

/**
 * @title PredictionMarket
 * @notice Core contract handling prediction markets
 * @dev Stores all markets in a single contract, identified by marketId
 */
contract PredictionMarket is Ownable, ReentrancyGuard, IPredictionMarket {
    using SafeERC20 for IERC20;

    /// @notice The payment token (cUSD)
    IERC20 public immutable paymentToken;

    /// @notice Platform fee percentage (basis points, e.g., 500 = 5%)
    uint256 public platformFeeBps = 500; // 5%

    /// @notice Creator fee percentage (basis points, e.g., 200 = 2%)
    uint256 public creatorFeeBps = 200; // 2%

    /// @notice Total number of markets created
    uint256 public marketCount;

    /// @notice Market data storage
    mapping(uint256 => MarketInfo) public markets;

    /// @notice Pool amounts per market and outcome
    mapping(uint256 => mapping(uint8 => uint256)) private _poolAmounts;

    /// @notice User predictions per market
    mapping(uint256 => mapping(address => Prediction)) public userPredictions;

    /// @notice Track if user has claimed payout
    mapping(uint256 => mapping(address => bool)) private _hasClaimed;

    /// @notice Prediction struct
    struct Prediction {
        address user;
        Outcome side;
        uint256 amount;
        uint256 timestamp;
    }

    /// @notice Event emitted when a market is created
    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string question,
        uint256 endTime
    );

    /// @notice Event emitted when a prediction is made
    event PredictionMade(
        uint256 indexed marketId,
        address indexed user,
        Outcome side,
        uint256 amount
    );

    /// @notice Event emitted when a market is resolved
    event MarketResolved(uint256 indexed marketId, Outcome winningOutcome);

    /// @notice Event emitted when payout is claimed
    event PayoutClaimed(uint256 indexed marketId, address indexed user, uint256 amount);

    /**
     * @notice Constructor
     * @param _paymentToken The payment token address (cUSD)
     * @param _owner The owner address
     */
    constructor(address _paymentToken, address _owner) Ownable(_owner) {
        require(_paymentToken != address(0), "PredictionMarket: invalid payment token");
        paymentToken = IERC20(_paymentToken);
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
    ) external returns (uint256 marketId) {
        require(bytes(question).length > 0, "PredictionMarket: empty question");
        require(endTime > block.timestamp, "PredictionMarket: invalid end time");
        require(initialStake > 0, "PredictionMarket: initial stake required");
        require(initialSide <= 1, "PredictionMarket: invalid side");

        marketCount++;
        marketId = marketCount;

        // Initialize market
        markets[marketId] = MarketInfo({
            id: marketId,
            question: question,
            category: category,
            creator: creator,
            yesPool: 0,
            noPool: 0,
            totalPool: 0,
            endTime: endTime,
            status: MarketStatus.Active,
            winningOutcome: Outcome.Yes,
            resolved: false
        });

        // Add initial stake to pool
        if (initialSide == 0) {
            markets[marketId].yesPool = initialStake;
        } else {
            markets[marketId].noPool = initialStake;
        }
        markets[marketId].totalPool = initialStake;

        _poolAmounts[marketId][initialSide] = initialStake;

        // Record creator's prediction
        userPredictions[marketId][creator] = Prediction({
            user: creator,
            side: Outcome(initialSide),
            amount: initialStake,
            timestamp: block.timestamp
        });

        emit MarketCreated(marketId, creator, question, endTime);
    }

    /**
     * @notice Get market information
     * @param marketId The market ID
     * @return MarketInfo struct with market details
     */
    function getMarketInfo(uint256 marketId) external view returns (MarketInfo memory) {
        return markets[marketId];
    }

    /**
     * @notice Get pool amount for a specific outcome
     * @param marketId The market ID
     * @param outcome The outcome (0 = Yes, 1 = No)
     * @return The pool amount
     */
    function poolAmounts(uint256 marketId, uint8 outcome) external view returns (uint256) {
        return _poolAmounts[marketId][outcome];
    }

    /**
     * @notice Get user's prediction for a specific market
     * @param marketId The market ID
     * @param user The user address
     * @return Prediction struct
     */
    function getUserPrediction(
        uint256 marketId,
        address user
    ) external view returns (Prediction memory) {
        return userPredictions[marketId][user];
    }

    /**
     * @notice Get odds for a side (as percentage, scaled by 100)
     * @param marketId The market ID
     * @param side The side (0 = Yes, 1 = No)
     * @return Odds as percentage (e.g., 6500 = 65%)
     */
    function getOdds(uint256 marketId, uint8 side) external view returns (uint256) {
        MarketInfo memory market = markets[marketId];
        if (market.totalPool == 0) {
            return 5000; // 50% if no pool
        }

        uint256 sidePool = side == 0 ? market.yesPool : market.noPool;
        return (sidePool * 10000) / market.totalPool;
    }

    /**
     * @notice Calculate potential winnings for a prediction
     * @param marketId The market ID
     * @param side The side (0 = Yes, 1 = No)
     * @param amount The stake amount
     * @return Potential winnings amount
     */
    function calculatePotentialWinnings(
        uint256 marketId,
        uint8 side,
        uint256 amount
    ) external view returns (uint256) {
        MarketInfo memory market = markets[marketId];
        if (market.totalPool == 0) {
            return amount; // Return stake if no pool
        }

        uint256 sidePool = side == 0 ? market.yesPool : market.noPool;
        uint256 newTotalPool = market.totalPool + amount;
        uint256 newSidePool = sidePool + amount;
        uint256 oppositePool = newTotalPool - newSidePool;

        if (oppositePool == 0) {
            return amount; // No opposite pool, return stake
        }

        // Calculate winnings: (stake * totalPool) / oppositePool
        uint256 grossWinnings = (amount * newTotalPool) / oppositePool;
        
        // Apply fees
        uint256 platformFee = (grossWinnings * platformFeeBps) / 10000;
        uint256 creatorFee = (grossWinnings * creatorFeeBps) / 10000;
        
        return grossWinnings - platformFee - creatorFee;
    }

    /**
     * @notice Get fees for a market
     * @param marketId The market ID
     * @return platformFee The platform fee percentage
     * @return creatorFee The creator fee percentage
     */
    function getFees(uint256 marketId) external view returns (uint256 platformFee, uint256 creatorFee) {
        return (platformFeeBps, creatorFeeBps);
    }

    /**
     * @notice Make a prediction
     * @param marketId The market ID
     * @param side The side (0 = Yes, 1 = No)
     * @param amount The stake amount
     */
    function predict(uint256 marketId, uint8 side, uint256 amount) external nonReentrant {
        MarketInfo memory market = markets[marketId];
        require(market.id != 0, "PredictionMarket: market does not exist");
        require(market.status == MarketStatus.Active, "PredictionMarket: market not active");
        require(block.timestamp < market.endTime, "PredictionMarket: market ended");
        require(side <= 1, "PredictionMarket: invalid side");
        require(amount > 0, "PredictionMarket: amount must be > 0");

        // Transfer tokens from user
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update pools
        if (side == 0) {
            markets[marketId].yesPool += amount;
        } else {
            markets[marketId].noPool += amount;
        }
        markets[marketId].totalPool += amount;
        _poolAmounts[marketId][side] += amount;

        // Update or create user prediction
        Prediction storage userPred = userPredictions[marketId][msg.sender];
        if (userPred.amount > 0) {
            // User already has a prediction, add to it
            require(userPred.side == Outcome(side), "PredictionMarket: cannot change side");
            userPred.amount += amount;
        } else {
            // New prediction
            userPredictions[marketId][msg.sender] = Prediction({
                user: msg.sender,
                side: Outcome(side),
                amount: amount,
                timestamp: block.timestamp
            });
        }

        emit PredictionMade(marketId, msg.sender, Outcome(side), amount);
    }

    /**
     * @notice Claim payout after market resolution
     * @param marketId The market ID
     */
    function claimPayout(uint256 marketId) external nonReentrant {
        MarketInfo memory market = markets[marketId];
        require(market.id != 0, "PredictionMarket: market does not exist");
        require(market.resolved, "PredictionMarket: market not resolved");
        require(!_hasClaimed[marketId][msg.sender], "PredictionMarket: already claimed");

        Prediction memory userPred = userPredictions[marketId][msg.sender];
        require(userPred.amount > 0, "PredictionMarket: no prediction");
        require(userPred.side == market.winningOutcome, "PredictionMarket: incorrect prediction");

        // Calculate winnings
        uint256 grossWinnings = (userPred.amount * market.totalPool) / 
            (market.winningOutcome == Outcome.Yes ? market.yesPool : market.noPool);
        
        // Apply fees
        uint256 platformFee = (grossWinnings * platformFeeBps) / 10000;
        uint256 creatorFee = (grossWinnings * creatorFeeBps) / 10000;
        uint256 netWinnings = grossWinnings - platformFee - creatorFee;

        // Mark as claimed
        _hasClaimed[marketId][msg.sender] = true;

        // Transfer winnings
        paymentToken.safeTransfer(msg.sender, netWinnings);

        emit PayoutClaimed(marketId, msg.sender, netWinnings);
    }

    /**
     * @notice Check if user has claimed payout
     * @param marketId The market ID
     * @param user The user address
     * @return True if user has claimed
     */
    function hasClaimed(uint256 marketId, address user) external view returns (bool) {
        return _hasClaimed[marketId][user];
    }

    /**
     * @notice Check if a market exists
     * @param marketId The market ID
     * @return True if market exists
     */
    function marketExists(uint256 marketId) external view returns (bool) {
        return markets[marketId].id != 0;
    }

    /**
     * @notice Get total number of markets
     * @return The total market count
     */
    function getMarketCount() external view returns (uint256) {
        return marketCount;
    }

    /**
     * @notice Resolve a market (called by Oracle)
     * @param marketId The market ID
     * @param outcome The winning outcome
     */
    function resolve(uint256 marketId, Outcome outcome) external {
        // TODO: Add access control for Oracle
        MarketInfo storage market = markets[marketId];
        require(market.id != 0, "PredictionMarket: market does not exist");
        require(!market.resolved, "PredictionMarket: already resolved");
        require(block.timestamp >= market.endTime, "PredictionMarket: market not ended");

        market.status = MarketStatus.Resolved;
        market.winningOutcome = outcome;
        market.resolved = true;

        emit MarketResolved(marketId, outcome);
    }
}

