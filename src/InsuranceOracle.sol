// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title InsuranceOracle
 * @dev Oracle contract for providing price feeds and event detection
 * This will be expanded to include trustless event detection later
 */
contract InsuranceOracle is Ownable, Pausable {
    
    // Events
    event PriceUpdated(string indexed asset, uint256 price, uint256 timestamp);
    event EventTriggered(uint256 indexed eventId, string reason, uint256 timestamp);
    event OracleAdded(address indexed oracle, string name);
    event OracleRemoved(address indexed oracle);

    // Structs
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
    }

    struct EventData {
        string name;
        string description;
        bool isTriggered;
        uint256 triggerTime;
        string triggerReason;
    }

    // State variables
    mapping(string => PriceData) public prices;
    mapping(uint256 => EventData) public events;
    mapping(address => bool) public authorizedOracles;
    mapping(string => address[]) public assetOracles;
    
    uint256 public constant PRICE_PRECISION = 1e8;
    uint256 public constant MIN_CONFIDENCE = 80; // 80% confidence required
    uint256 public constant PRICE_STALENESS = 1 hours; // 1 hour max staleness

    modifier onlyOracle() {
        require(authorizedOracles[msg.sender], "Not authorized oracle");
        _;
    }

    constructor() {
        // Initialize with some common assets
        _initializeAssets();
    }

    /**
     * @dev Initialize common assets
     */
    function _initializeAssets() internal {
        string[] memory assets = new string[](5);
        assets[0] = "BTC";
        assets[1] = "ETH";
        assets[2] = "AAVE";
        assets[3] = "USDC";
        assets[4] = "USDT";
        
        for (uint256 i = 0; i < assets.length; i++) {
            prices[assets[i]] = PriceData({
                price: 0,
                timestamp: 0,
                confidence: 0
            });
        }
    }

    /**
     * @dev Add authorized oracle
     */
    function addOracle(address oracle, string memory name) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        authorizedOracles[oracle] = true;
        emit OracleAdded(oracle, name);
    }

    /**
     * @dev Remove authorized oracle
     */
    function removeOracle(address oracle) external onlyOwner {
        authorizedOracles[oracle] = false;
        emit OracleRemoved(oracle);
    }

    /**
     * @dev Update price for an asset
     */
    function updatePrice(
        string memory asset,
        uint256 price,
        uint256 confidence
    ) external onlyOracle whenNotPaused {
        require(confidence >= MIN_CONFIDENCE, "Insufficient confidence");
        require(price > 0, "Invalid price");
        
        prices[asset] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: confidence
        });
        
        emit PriceUpdated(asset, price, block.timestamp);
    }

    /**
     * @dev Get current price for an asset
     */
    function getPrice(string memory asset) external view returns (uint256) {
        PriceData memory data = prices[asset];
        require(data.timestamp > 0, "No price data");
        require(block.timestamp - data.timestamp <= PRICE_STALENESS, "Price too stale");
        return data.price;
    }

    /**
     * @dev Get price data with confidence
     */
    function getPriceData(string memory asset) external view returns (PriceData memory) {
        return prices[asset];
    }

    /**
     * @dev Calculate price change percentage
     */
    function getPriceChange(
        string memory asset,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external view returns (int256) {
        // This would need historical price data storage
        // For now, return placeholder
        return 0;
    }

    /**
     * @dev Check if BTC dropped more than 20% in one day
     */
    function checkBTCCrash() external view returns (bool) {
        // This would compare current price with 24h ago
        // For now, return false
        return false;
    }

    /**
     * @dev Check if AAVE was hacked (placeholder for now)
     */
    function checkAAVEHack() external view returns (bool) {
        // This would check various indicators of a hack
        // For now, return false
        return false;
    }

    /**
     * @dev Trigger an event manually (for testing)
     */
    function triggerEvent(uint256 eventId, string memory reason) external onlyOwner {
        events[eventId] = EventData({
            name: "",
            description: "",
            isTriggered: true,
            triggerTime: block.timestamp,
            triggerReason: reason
        });
        
        emit EventTriggered(eventId, reason, block.timestamp);
    }

    /**
     * @dev Get event data
     */
    function getEventData(uint256 eventId) external view returns (EventData memory) {
        return events[eventId];
    }

    /**
     * @dev Pause oracle operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause oracle operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency function to update price if oracle fails
     */
    function emergencyUpdatePrice(
        string memory asset,
        uint256 price
    ) external onlyOwner {
        prices[asset] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: 100
        });
        
        emit PriceUpdated(asset, price, block.timestamp);
    }
} 