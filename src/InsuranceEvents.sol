// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract InsuranceEvents {
    struct Event {
        string name;
        string description;
        uint256 triggerThreshold;
        bool isTriggered;
        uint256 triggerTime;
        uint256 totalCoverage;
        uint256 totalPremiums;
        uint256 basePremium;
        bool isActive;
        uint256 totalInsurerCapital;
        uint256 lastPremiumDistribution;
        uint256 accumulatedPremiums;
    }

    mapping(uint256 => Event) public events;

    event InsurerRegistered(address indexed insurer, uint256 collateral);
    event ReinsurerRegistered(address indexed reinsurer, uint256 collateral);
    event PolicyCreated(uint256 indexed policyId, address indexed policyHolder, uint256 eventId, uint256 premium, uint256 coverage);
    event PolicyActivated(uint256 indexed policyId, uint256 activationTime);
    event PolicyClaimed(uint256 indexed policyId, uint256 payout);
    event EventAllocationAdded(address indexed insurer, uint256 eventId, uint256 amount);
    event EventAllocationRemoved(address indexed insurer, uint256 eventId, uint256 amount);
    event CapitalConsumed(address indexed insurer, uint256 amount);
    event PremiumDistributed(address indexed recipient, uint256 amount, uint256 eventId);
    event PremiumUpdated(uint256 eventId, uint256 newPremium);

    uint256 private _eventIds;

    function getEvent(uint256 eventId) external view returns (
        string memory name,
        string memory description,
        uint256 triggerThreshold,
        bool isTriggered,
        uint256 triggerTime,
        uint256 totalCoverage,
        uint256 totalPremiums,
        uint256 basePremium,
        bool isActive,
        uint256 totalInsurerCapital,
        uint256 lastPremiumDistribution,
        uint256 accumulatedPremiums
    ) {
        Event storage e = events[eventId];
        return (
            e.name,
            e.description,
            e.triggerThreshold,
            e.isTriggered,
            e.triggerTime,
            e.totalCoverage,
            e.totalPremiums,
            e.basePremium,
            e.isActive,
            e.totalInsurerCapital,
            e.lastPremiumDistribution,
            e.accumulatedPremiums
        );
    }

    function registerEvent(
        string memory name,
        string memory description,
        uint256 triggerThreshold,
        uint256 basePremium
    ) external returns (uint256) {
        _eventIds++;
        uint256 eventId = _eventIds;
        events[eventId] = Event({
            name: name,
            description: description,
            triggerThreshold: triggerThreshold,
            isTriggered: false,
            triggerTime: 0,
            totalCoverage: 0,
            totalPremiums: 0,
            basePremium: basePremium,
            isActive: true,
            totalInsurerCapital: 0,
            lastPremiumDistribution: block.timestamp,
            accumulatedPremiums: 0
        });
        return eventId;
    }

    function triggerEvent(uint256 eventId) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        events[eventId].isTriggered = true;
        events[eventId].triggerTime = block.timestamp;
    }

    function calculatePremium(uint256 eventId, uint256 coverage) external view returns (uint256) {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        require(coverage > 0, "Coverage must be > 0");
        return events[eventId].basePremium * coverage / 1e18;
    }
}

interface IInsuranceEvents {
    function getEvent(uint256 eventId) external view returns (
        string memory name,
        string memory description,
        uint256 triggerThreshold,
        bool isTriggered,
        uint256 triggerTime,
        uint256 totalCoverage,
        uint256 totalPremiums,
        uint256 basePremium,
        bool isActive,
        uint256 totalInsurerCapital,
        uint256 lastPremiumDistribution,
        uint256 accumulatedPremiums
    );
    function registerEvent(
        string memory name,
        string memory description,
        uint256 triggerThreshold,
        uint256 basePremium
    ) external returns (uint256);
    function triggerPremiumDistribution() external;
    function distributeAccumulatedPremiums() external;
    function hasAccumulatedPremiums() external view returns (bool);
    function getTotalAccumulatedPremiums() external view returns (uint256);
    function triggerEvent(uint256 eventId) external;
    function calculatePremium(uint256 eventId, uint256 coverage) external view returns (uint256);
} 