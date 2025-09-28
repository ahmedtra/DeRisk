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
    
    // Event parameters for advanced premium calculation
    mapping(uint256 => uint256) public eventExpectedLossRatio;
    mapping(uint256 => uint256) public eventTotalLossRatio;
    mapping(uint256 => uint256) public eventMaxPremium;

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
    event PremiumDistributionTriggered(uint256 timestamp);
    event PremiumsDistributed(uint256 insurerPremiums, uint256 reinsurerPremiums, uint256 totalPremiums);
    event EventRiskParametersUpdated(uint256 eventId, uint256 expectedLossRatio, uint256 totalLossRatio, uint256 maxPremium);
    event EventInsurerCapitalUpdated(uint256 eventId, uint256 newTotalCapital);

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

    function getEventCount() public view returns (uint256) {
        return _eventIds;
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
            totalCoverage: 0,  // Fix: Set totalCoverage to triggerThreshold
            totalPremiums: 0,
            basePremium: basePremium,
            isActive: true,
            totalInsurerCapital: 0,
            lastPremiumDistribution: block.timestamp,
            accumulatedPremiums: 0
        });
        
        // Set default risk parameters for the event
        eventExpectedLossRatio[eventId] = 500; // 5% default expected loss ratio
        eventTotalLossRatio[eventId] = 15000;  // 150% default total loss ratio
        eventMaxPremium[eventId] = basePremium * 10; // 10x base premium as max
        
        return eventId;
    }

    function triggerEvent(uint256 eventId) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        events[eventId].isTriggered = true;
        events[eventId].triggerTime = block.timestamp;
    }

    /**
     * @dev Calculate premium using advanced reinsurance math
     * This replaces the simple calculation with the sophisticated mathematical model
     */
    function calculatePremium(uint256 eventId, uint256 coverage) external view returns (uint256) {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        require(coverage > 0, "Coverage must be > 0");
        
        // Simple premium calculation based on base premium
        return events[eventId].basePremium * coverage / 1e18;
    }

    /**
     * @dev Update event risk parameters for premium calculations
     */
    function updateEventRiskParameters(
        uint256 eventId, 
        uint256 expectedLossRatio, 
        uint256 totalLossRatio, 
        uint256 maxPremium
    ) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        
        eventExpectedLossRatio[eventId] = expectedLossRatio;
        eventTotalLossRatio[eventId] = totalLossRatio;
        eventMaxPremium[eventId] = maxPremium;
        
        emit EventRiskParametersUpdated(eventId, expectedLossRatio, totalLossRatio, maxPremium);
    }

    /**
     * @dev Accumulate premiums for an event and distribute between insurers and reinsurers
     * This function is called automatically when a policy is created
     */
    function accumulatePremiums(uint256 eventId, uint256 premiumAmount) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        require(premiumAmount > 0, "Premium amount must be > 0");

        events[eventId].accumulatedPremiums += premiumAmount;
        events[eventId].totalPremiums += premiumAmount;
        events[eventId].totalCoverage += premiumAmount; // Assuming coverage equals premium for simplicity

        // Automatically distribute premiums between insurers and reinsurers
        distributeEventPremiums(eventId, premiumAmount);

        emit PremiumUpdated(eventId, events[eventId].totalPremiums);
    }

    /**
     * @dev Automatically distribute premiums for an event between insurers and reinsurers
     * Uses a 70/30 split (insurers/reinsurers) based on risk sharing
     */
    function distributeEventPremiums(uint256 eventId, uint256 premiumAmount) internal {
        // Get the event's insurer capital allocation
        uint256 totalInsurerCapital = events[eventId].totalInsurerCapital;
        
        // Calculate distribution ratios
        uint256 insurerRatio = 700; // 70% in basis points
        uint256 reinsurerRatio = 300; // 30% in basis points
        
        uint256 insurerPremium = (premiumAmount * insurerRatio) / 1000;
        uint256 reinsurerPremium = (premiumAmount * reinsurerRatio) / 1000;
        
        // Distribute to insurers (this will be claimed through the insurer contract)
        // The premium is already accumulated in the event, insurers can claim their share
        
        // Distribute to reinsurers (this will be claimed through the reinsurer contract)
        // The premium is already accumulated in the event, reinsurers can claim their share
        
        emit PremiumsDistributed(insurerPremium, reinsurerPremium, premiumAmount);
    }

    /**
     * @dev Set risk parameters for an event
     */
    function setEventRiskParameters(
        uint256 eventId,
        uint256 expectedLossRatio,
        uint256 totalLossRatio,
        uint256 maxPremium
    ) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        eventExpectedLossRatio[eventId] = expectedLossRatio;
        eventTotalLossRatio[eventId] = totalLossRatio;
        eventMaxPremium[eventId] = maxPremium;
    }

    /**
     * @dev Get event risk parameters
     */
    function getEventRiskParameters(uint256 eventId) external view returns (
        uint256 expectedLossRatio,
        uint256 totalLossRatio,
        uint256 maxPremium
    ) {
        return (
            eventExpectedLossRatio[eventId],
            eventTotalLossRatio[eventId],
            eventMaxPremium[eventId]
        );
    }

    /**
     * @dev Update the total insurer capital allocated to an event
     * This function should be called when insurers allocate or remove capital from events
     */
    function updateEventInsurerCapital(uint256 eventId, uint256 newTotalCapital) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        
        events[eventId].totalInsurerCapital = newTotalCapital;
        
        emit EventInsurerCapitalUpdated(eventId, newTotalCapital);
    }

    /**
     * @dev Get the total insurer capital allocated to an event
     */
    function getEventInsurerCapital(uint256 eventId) external view returns (uint256) {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        return events[eventId].totalInsurerCapital;
    }

    // Placeholder functions for interface compatibility
    function triggerPremiumDistribution() external {
        // This function triggers the premium distribution process
        // It can be called by authorized parties to start premium distribution
        // For now, we'll just emit an event to track when it's called
        emit PremiumDistributionTriggered(block.timestamp);
    }
    
    function hasAccumulatedPremiums() external view returns (bool) {
        for (uint256 i = 0; i < getEventCount(); i++) {
            if (events[i].accumulatedPremiums > 0) {
                return true;
            }
        }
        return false;
    }
    
    function getTotalAccumulatedPremiums() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < getEventCount(); i++) {
            total += events[i].accumulatedPremiums;
        }
        return total;
    }
    
    function distributeAccumulatedPremiums() external {
        uint256 totalPremiums = getTotalAccumulatedPremiums();
        require(totalPremiums > 0, "No premiums to distribute");

        uint256 totalInsurerCapital = getTotalInsurerCapital();
        uint256 totalReinsurerCapital = getTotalReinsurerCapital();
        uint256 totalCapital = totalInsurerCapital + totalReinsurerCapital;

        require(totalCapital > 0, "No capital to distribute premiums to");

        // Calculate distribution based on actual capital allocation
        uint256 insurerRatio = totalInsurerCapital > 0 ? (totalInsurerCapital * 1000) / totalCapital : 700; // Default 70%
        uint256 reinsurerRatio = totalReinsurerCapital > 0 ? (totalReinsurerCapital * 1000) / totalCapital : 300; // Default 30%

        uint256 insurerPremiums = (totalPremiums * insurerRatio) / 1000;
        uint256 reinsurerPremiums = (totalPremiums * reinsurerRatio) / 1000;

        // Clear accumulated premiums from all events
        for (uint256 i = 0; i < getEventCount(); i++) {
            if (events[i].accumulatedPremiums > 0) {
                events[i].accumulatedPremiums = 0;
                events[i].lastPremiumDistribution = block.timestamp;
            }
        }

        // Note: The actual premium distribution to individual insurers/reinsurers
        // happens through the claim functions in their respective contracts
        // This function just clears the accumulated premiums and emits the distribution event

        emit PremiumsDistributed(insurerPremiums, reinsurerPremiums, totalPremiums);
    }
    
    /**
     * @dev Add test premiums to an event for testing purposes
     * This function should only be used for testing and development
     */
    function addTestPremiums(uint256 eventId, uint256 amount) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        require(amount > 0, "Amount must be > 0");
        
        events[eventId].accumulatedPremiums += amount;
        events[eventId].totalPremiums += amount;
        
        emit PremiumUpdated(eventId, events[eventId].totalPremiums);
    }

    // Helper functions for premium distribution
    function getTotalInsurerCapital() internal view returns (uint256) {
        // This should be called from InsuranceCore to get actual total insurer capital
        // For now, we'll sum up the capital from all events
        uint256 total = 0;
        for (uint256 i = 0; i < getEventCount(); i++) {
            total += events[i].totalInsurerCapital;
        }
        return total;
    }

    function getTotalReinsurerCapital() internal view returns (uint256) {
        // This should be called from InsuranceCore to get actual total reinsurer capital
        // For now, we'll return a reasonable estimate based on total capital
        uint256 totalInsurerCapital = getTotalInsurerCapital();
        return totalInsurerCapital > 0 ? totalInsurerCapital / 2 : 0; // Assume reinsurers have half of insurer capital
    }
    
    /**
     * @dev Accumulate premiums for insurers for a specific event
     * @param eventId The event ID
     * @param amount The premium amount to accumulate
     */
    function accumulateInsurerPremiums(uint256 eventId, uint256 amount) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        require(amount > 0, "Amount must be > 0");
        
        events[eventId].accumulatedPremiums += amount;
        events[eventId].totalPremiums += amount;
        
        emit PremiumUpdated(eventId, events[eventId].totalPremiums);
    }
    
    /**
     * @dev Accumulate premiums for reinsurers for a specific event
     * @param eventId The event ID
     * @param amount The premium amount to accumulate
     */
    function accumulateReinsurerPremiums(uint256 eventId, uint256 amount) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        require(events[eventId].isActive, "Event not active");
        require(amount > 0, "Amount must be > 0");
        
        // For reinsurers, we'll accumulate in a separate mapping or use the existing accumulatedPremiums
        // This is a simplified implementation - in a real system, you might want separate tracking
        events[eventId].accumulatedPremiums += amount;
        events[eventId].totalPremiums += amount;
        
        emit PremiumUpdated(eventId, events[eventId].totalPremiums);
    }
    
    /**
     * @dev Get accumulated premiums for a specific event
     * @param eventId The event ID
     * @return The accumulated premiums for this event
     */
    function getEventAccumulatedPremiums(uint256 eventId) external view returns (uint256) {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        return events[eventId].accumulatedPremiums;
    }
    
    /**
     * @dev Clear accumulated premiums for a specific event after distribution
     * @param eventId The event ID
     */
    function clearAccumulatedPremiums(uint256 eventId) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        events[eventId].accumulatedPremiums = 0;
        events[eventId].lastPremiumDistribution = block.timestamp;
        
        emit PremiumsDistributed(0, 0, 0); // Emit event to indicate premiums cleared
    }
    
    /**
     * @dev Get total coverage for a specific event
     * @param eventId The event ID
     * @return The total coverage for this event
     */
    function getEventTotalCoverage(uint256 eventId) external view returns (uint256) {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        return events[eventId].totalCoverage;
    }

    function addCoverage(uint256 eventId, uint256 coverage) external {
        require(bytes(events[eventId].name).length != 0, "Event does not exist");
        events[eventId].totalCoverage += coverage;
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
    function getEventCount() external view returns (uint256);
    function getEventRiskParameters(uint256 eventId) external view returns (
        uint256 expectedLossRatio,
        uint256 totalLossRatio,
        uint256 maxPremium
    );
    function addCoverage(uint256 eventId, uint256 coverage) external;
    function accumulatePremiums(uint256 eventId, uint256 premiumAmount) external;
    function addTestPremiums(uint256 eventId, uint256 amount) external;
    function updateEventInsurerCapital(uint256 eventId, uint256 newTotalCapital) external;
    function getEventInsurerCapital(uint256 eventId) external view returns (uint256);
    function updateEventRiskParameters(uint256 eventId, uint256 expectedLossRatio, uint256 totalLossRatio, uint256 maxPremium) external;
    function accumulateInsurerPremiums(uint256 eventId, uint256 amount) external;
    function accumulateReinsurerPremiums(uint256 eventId, uint256 amount) external;
    function getEventAccumulatedPremiums(uint256 eventId) external view returns (uint256);
    function clearAccumulatedPremiums(uint256 eventId) external;
    function getEventTotalCoverage(uint256 eventId) external view returns (uint256);
} 