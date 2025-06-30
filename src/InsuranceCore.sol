// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title InsuranceCore
 * @dev Core insurance contract for hedging against tail events
 * Features:
 * - Policy holders can buy insurance against specific events
 * - Two-layer insurance system (insurers and reinsurers)
 * - Dynamic premium pricing based on collateral and demand
 * - 7-day lockup period for new policies
 * - Capital allocation to specific events
 * - Continuous premium distribution based on dynamic APY
 */
contract InsuranceCore is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    IERC20 public paymentToken;
    
    uint256 public constant LOCKUP_PERIOD = 7 days;
    uint256 public constant MIN_COLLATERAL = 1000 * 1e18; // 1000 tokens
    uint256 public constant TARGET_APY_INSURER = 1500; // 15% base APY for insurers
    uint256 public constant TARGET_APY_REINSURER = 1000; // 10% base APY for reinsurers
    
    // Continuous distribution tracking
    uint256 public lastDistributionTime;
    uint256 public constant DISTRIBUTION_INTERVAL = 1 seconds; // Distribute every second
    
    Counters.Counter private _policyIds;
    Counters.Counter private _eventIds;

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
        uint256 lastPremiumDistribution; // Track last distribution time for this event
        uint256 accumulatedPremiums; // Accumulated premiums for distribution
    }

    struct Policy {
        address policyHolder;
        uint256 eventId;
        uint256 coverage;
        uint256 premium;
        uint256 startTime;
        uint256 activationTime;
        bool isActive;
        bool isClaimed;
    }

    struct Insurer {
        uint256 totalCollateral;
        uint256 availableCollateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
        uint256[] insuredPolicies;
        uint256[] allocatedEvents;
        mapping(uint256 => uint256) eventAllocations; // eventId => allocated amount
        uint256 lastPremiumClaim; // Track last premium claim time
        uint256 accumulatedPremiums; // Accumulated premiums for this insurer
    }

    struct Reinsurer {
        uint256 collateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
        uint256 lastPremiumClaim; // Track last premium claim time
        uint256 accumulatedPremiums; // Accumulated premiums for this reinsurer
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => Policy) public policies;
    mapping(address => Insurer) public insurers;
    mapping(address => Reinsurer) public reinsurers;
    
    address[] public insurerList;
    address[] public reinsurerList;
    
    // Event-specific insurer tracking
    mapping(uint256 => address[]) public eventInsurers; // eventId => insurer addresses

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
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address _paymentToken) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentToken);
        lastDistributionTime = block.timestamp;
    }

    /**
     * @dev Register as an insurer
     */
    function registerInsurer(uint256 collateral) external nonReentrant {
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        require(!insurers[msg.sender].isActive, "Already registered");
        
        paymentToken.transferFrom(msg.sender, address(this), collateral);
        
        Insurer storage insurer = insurers[msg.sender];
        insurer.totalCollateral = collateral;
        insurer.availableCollateral = collateral;
        insurer.consumedCapital = 0;
        insurer.totalPremiums = 0;
        insurer.isActive = true;
        insurer.lastPremiumClaim = block.timestamp;
        insurer.accumulatedPremiums = 0;
        delete insurer.insuredPolicies;
        delete insurer.allocatedEvents;
        // mapping eventAllocations is left as-is (auto-initialized)
        
        insurerList.push(msg.sender);
        
        emit InsurerRegistered(msg.sender, collateral);
    }

    /**
     * @dev Register as a reinsurer
     */
    function registerReinsurer(uint256 collateral) external nonReentrant {
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        require(!reinsurers[msg.sender].isActive, "Already registered");
        
        paymentToken.transferFrom(msg.sender, address(this), collateral);
        
        Reinsurer storage reinsurer = reinsurers[msg.sender];
        reinsurer.collateral = collateral;
        reinsurer.consumedCapital = 0;
        reinsurer.totalPremiums = 0;
        reinsurer.isActive = true;
        reinsurer.lastPremiumClaim = block.timestamp;
        reinsurer.accumulatedPremiums = 0;
        
        reinsurerList.push(msg.sender);
        
        emit ReinsurerRegistered(msg.sender, collateral);
    }

    /**
     * @dev Register a new insurance event
     */
    function registerEvent(string memory name, string memory description, uint256 triggerThreshold, uint256 basePremium) external onlyOwner {
        _eventIds.increment();
        uint256 eventId = _eventIds.current();
        
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
    }

    /**
     * @dev Allocate capital to a specific event
     */
    function allocateToEvent(uint256 eventId, uint256 amount) external nonReentrant {
        require(insurers[msg.sender].isActive, "Not registered as insurer");
        require(events[eventId].isActive, "Event not active");
        require(amount > 0, "Amount must be greater than 0");
        require(insurers[msg.sender].availableCollateral >= amount, "Insufficient available collateral");
        
        // Distribute accumulated premiums before reallocation
        distributeAccumulatedPremiums();
        
        insurers[msg.sender].availableCollateral -= amount;
        insurers[msg.sender].eventAllocations[eventId] += amount;
        
        // Add to allocated events list if not already there
        bool alreadyAllocated = false;
        for (uint256 i = 0; i < insurers[msg.sender].allocatedEvents.length; i++) {
            if (insurers[msg.sender].allocatedEvents[i] == eventId) {
                alreadyAllocated = true;
                break;
            }
        }
        if (!alreadyAllocated) {
            insurers[msg.sender].allocatedEvents.push(eventId);
        }
        
        // Add to event insurers list if not already there
        bool alreadyInList = false;
        for (uint256 i = 0; i < eventInsurers[eventId].length; i++) {
            if (eventInsurers[eventId][i] == msg.sender) {
                alreadyInList = true;
                break;
            }
        }
        if (!alreadyInList) {
            eventInsurers[eventId].push(msg.sender);
        }
        
        events[eventId].totalInsurerCapital += amount;
        
        emit EventAllocationAdded(msg.sender, eventId, amount);
    }

    /**
     * @dev Remove capital allocation from a specific event
     */
    function removeFromEvent(uint256 eventId, uint256 amount) external nonReentrant {
        require(insurers[msg.sender].isActive, "Not registered as insurer");
        require(insurers[msg.sender].eventAllocations[eventId] >= amount, "Insufficient allocation");
        require(amount > 0, "Amount must be greater than 0");
        
        // Distribute accumulated premiums before removal
        distributeAccumulatedPremiums();
        
        insurers[msg.sender].availableCollateral += amount;
        insurers[msg.sender].eventAllocations[eventId] -= amount;
        
        events[eventId].totalInsurerCapital -= amount;
        
        // Remove from allocated events if allocation becomes 0
        if (insurers[msg.sender].eventAllocations[eventId] == 0) {
            for (uint256 i = 0; i < insurers[msg.sender].allocatedEvents.length; i++) {
                if (insurers[msg.sender].allocatedEvents[i] == eventId) {
                    insurers[msg.sender].allocatedEvents[i] = insurers[msg.sender].allocatedEvents[insurers[msg.sender].allocatedEvents.length - 1];
                    insurers[msg.sender].allocatedEvents.pop();
                    break;
                }
            }
        }
        
        emit EventAllocationRemoved(msg.sender, eventId, amount);
    }

    /**
     * @dev Buy insurance policy
     */
    function buyPolicy(uint256 eventId, uint256 coverage) external nonReentrant {
        Event storage eventData = events[eventId];
        require(eventData.isActive, "Event not active");
        require(!eventData.isTriggered, "Event already triggered");
        
        // Check if there are active insurers for this event
        require(eventData.totalInsurerCapital > 0, "No active insurers for this event");
        
        uint256 premium = calculatePremium(eventId, coverage);
        require(premium > 0, "Invalid premium");
        
        paymentToken.transferFrom(msg.sender, address(this), premium);
        
        _policyIds.increment();
        uint256 policyId = _policyIds.current();
        
        policies[policyId] = Policy({
            policyHolder: msg.sender,
            eventId: eventId,
            coverage: coverage,
            premium: premium,
            startTime: block.timestamp,
            activationTime: block.timestamp + LOCKUP_PERIOD,
            isActive: false,
            isClaimed: false
        });
        
        eventData.totalCoverage += coverage;
        eventData.totalPremiums += premium;
        eventData.accumulatedPremiums += premium; // Add to accumulated premiums for distribution
        
        emit PolicyCreated(policyId, msg.sender, eventId, premium, coverage);
    }

    /**
     * @dev Activate policy after lockup period
     */
    function activatePolicy(uint256 policyId) external {
        Policy storage policy = policies[policyId];
        require(policy.policyHolder == msg.sender, "Not policy holder");
        require(block.timestamp >= policy.activationTime, "Lockup not expired");
        require(!policy.isActive, "Already active");
        
        policy.isActive = true;
        emit PolicyActivated(policyId, block.timestamp);
    }

    /**
     * @dev Trigger an event (for now, manual input)
     */
    function triggerEvent(uint256 eventId) external onlyOwner {
        Event storage eventData = events[eventId];
        require(eventData.isActive, "Event not active");
        require(!eventData.isTriggered, "Already triggered");
        
        eventData.isTriggered = true;
        eventData.triggerTime = block.timestamp;
        
        // Process all active policies for this event
        processEventClaims(eventId);
    }

    /**
     * @dev Calculate dynamic premium based on demand and supply
     */
    function calculatePremium(uint256 eventId, uint256 coverage) public view returns (uint256) {
        Event storage eventData = events[eventId];
        uint256 basePremium = eventData.basePremium;
        
        // Adjust based on total coverage vs available capital for this event
        uint256 demandRatio = eventData.totalCoverage > 0 ? 
            (eventData.totalCoverage * 1e18) / eventData.totalInsurerCapital : 1e18;
        
        // Premium increases with demand
        uint256 adjustedPremium = basePremium + (basePremium * demandRatio) / 1e18;
        
        return (coverage * adjustedPremium) / 1e18;
    }

    /**
     * @dev Public function to trigger premium distribution - can be called by anyone
     * This allows for automatic premium collection without requiring owner intervention
     */
    function triggerPremiumDistribution() external {
        distributeAccumulatedPremiums();
    }

    /**
     * @dev Distribute accumulated premiums continuously
     */
    function distributeAccumulatedPremiums() public {
        uint256 currentTime = block.timestamp;
        
        // Only distribute if enough time has passed
        if (currentTime < lastDistributionTime + DISTRIBUTION_INTERVAL) {
            return;
        }
        
        lastDistributionTime = currentTime;
        
        // Distribute premiums for each event
        for (uint256 eventId = 1; eventId <= _eventIds.current(); eventId++) {
            Event storage eventData = events[eventId];
            if (eventData.isActive && !eventData.isTriggered && eventData.accumulatedPremiums > 0) {
                distributeEventPremiums(eventId);
            }
        }
    }

    /**
     * @dev Distribute premiums for a specific event
     */
    function distributeEventPremiums(uint256 eventId) internal {
        Event storage eventData = events[eventId];
        uint256 totalReinsurerCapital = getTotalReinsurerCapital();
        
        if (eventData.totalInsurerCapital > 0) {
            // 70% to insurers of this event, 30% to reinsurers
            uint256 insurerShare = (eventData.accumulatedPremiums * 70) / 100;
            uint256 reinsurerShare = eventData.accumulatedPremiums - insurerShare;
            
            // Distribute among active insurers of this event proportionally
            distributeAmongEventInsurers(insurerShare, eventId);
            
            // Distribute among reinsurers proportionally
            if (totalReinsurerCapital > 0) {
                distributeAmongReinsurers(reinsurerShare);
            }
            
            // Reset accumulated premiums for this event
            eventData.accumulatedPremiums = 0;
            eventData.lastPremiumDistribution = block.timestamp;
        }
    }

    /**
     * @dev Distribute premium among insurers of a specific event
     */
    function distributeAmongEventInsurers(uint256 amount, uint256 eventId) internal {
        address[] storage eventInsurerList = eventInsurers[eventId];
        uint256 totalCapital = 0;
        
        for (uint256 i = 0; i < eventInsurerList.length; i++) {
            address insurer = eventInsurerList[i];
            if (insurers[insurer].isActive) {
                totalCapital += insurers[insurer].eventAllocations[eventId];
            }
        }
        
        for (uint256 i = 0; i < eventInsurerList.length; i++) {
            address insurer = eventInsurerList[i];
            if (insurers[insurer].isActive) {
                uint256 allocation = insurers[insurer].eventAllocations[eventId];
                if (allocation > 0) {
                    uint256 share = (amount * allocation) / totalCapital;
                    insurers[insurer].totalPremiums += share;
                    insurers[insurer].accumulatedPremiums += share;
                    emit PremiumDistributed(insurer, share, eventId);
                }
            }
        }
    }

    /**
     * @dev Distribute premium among reinsurers
     */
    function distributeAmongReinsurers(uint256 amount) internal {
        uint256 totalCapital = getTotalReinsurerCapital();
        
        for (uint256 i = 0; i < reinsurerList.length; i++) {
            address reinsurer = reinsurerList[i];
            if (reinsurers[reinsurer].isActive) {
                uint256 share = (amount * reinsurers[reinsurer].collateral) / totalCapital;
                reinsurers[reinsurer].totalPremiums += share;
                reinsurers[reinsurer].accumulatedPremiums += share;
                emit PremiumDistributed(reinsurer, share, 0); // 0 indicates reinsurer distribution
            }
        }
    }

    /**
     * @dev Claim accumulated premiums for insurers
     */
    function claimInsurerPremiums() external nonReentrant {
        require(insurers[msg.sender].isActive, "Not registered as insurer");
        require(insurers[msg.sender].accumulatedPremiums > 0, "No premiums to claim");
        
        uint256 amount = insurers[msg.sender].accumulatedPremiums;
        insurers[msg.sender].accumulatedPremiums = 0;
        insurers[msg.sender].lastPremiumClaim = block.timestamp;
        
        paymentToken.transfer(msg.sender, amount);
    }

    /**
     * @dev Claim accumulated premiums for reinsurers
     */
    function claimReinsurerPremiums() external nonReentrant {
        require(reinsurers[msg.sender].isActive, "Not registered as reinsurer");
        require(reinsurers[msg.sender].accumulatedPremiums > 0, "No premiums to claim");
        
        uint256 amount = reinsurers[msg.sender].accumulatedPremiums;
        reinsurers[msg.sender].accumulatedPremiums = 0;
        reinsurers[msg.sender].lastPremiumClaim = block.timestamp;
        
        paymentToken.transfer(msg.sender, amount);
    }

    /**
     * @dev Calculate dynamic APY for an event based on current market conditions
     */
    function calculateEventAPY(uint256 eventId) public view returns (uint256) {
        Event storage eventData = events[eventId];
        if (eventData.totalInsurerCapital == 0) return 0;
        
        // Base APY calculation
        uint256 baseAPY = TARGET_APY_INSURER;
        
        // Adjust based on utilization rate
        uint256 utilizationRate = (eventData.totalCoverage * 10000) / eventData.totalInsurerCapital;
        
        // Higher utilization = higher APY (up to 2x base)
        uint256 utilizationMultiplier = 10000 + (utilizationRate * 5000) / 10000; // 1x to 1.5x
        
        // Adjust based on premium accumulation rate
        uint256 premiumRate = eventData.accumulatedPremiums > 0 ? 
            (eventData.accumulatedPremiums * 10000) / eventData.totalInsurerCapital : 0;
        
        uint256 premiumMultiplier = 10000 + (premiumRate * 2000) / 10000; // 1x to 1.2x
        
        uint256 finalAPY = (baseAPY * utilizationMultiplier * premiumMultiplier) / 100000000;
        
        return Math.min(finalAPY, 5000); // Cap at 50% APY
    }

    /**
     * @dev Process claims when event is triggered
     */
    function processEventClaims(uint256 eventId) internal {
        for (uint256 i = 1; i <= _policyIds.current(); i++) {
            Policy storage policy = policies[i];
            if (policy.eventId == eventId && policy.isActive && !policy.isClaimed) {
                processClaim(i);
            }
        }
    }

    /**
     * @dev Process individual claim
     */
    function processClaim(uint256 policyId) internal {
        Policy storage policy = policies[policyId];
        Event storage eventData = events[policy.eventId];
        
        require(eventData.isTriggered, "Event not triggered");
        require(policy.isActive, "Policy not active");
        require(!policy.isClaimed, "Already claimed");
        
        policy.isClaimed = true;
        
        // Pay out coverage
        paymentToken.transfer(policy.policyHolder, policy.coverage);
        
        // Consume insurer and reinsurer capital
        consumeCapital(policy.coverage, policy.eventId);
        
        emit PolicyClaimed(policyId, policy.coverage);
    }

    /**
     * @dev Consume capital from insurers and reinsurers
     */
    function consumeCapital(uint256 amount, uint256 eventId) internal {
        uint256 eventInsurerCapital = events[eventId].totalInsurerCapital;
        uint256 totalReinsurerCapital = getTotalReinsurerCapital();
        
        // 70% from insurers of this event, 30% from reinsurers
        uint256 insurerShare = (amount * 70) / 100;
        uint256 reinsurerShare = amount - insurerShare;
        
        consumeEventInsurerCapital(insurerShare, eventId);
        consumeReinsurerCapital(reinsurerShare);
    }

    /**
     * @dev Consume insurer capital for a specific event proportionally
     */
    function consumeEventInsurerCapital(uint256 amount, uint256 eventId) internal {
        address[] storage eventInsurerList = eventInsurers[eventId];
        uint256 totalCapital = 0;
        
        for (uint256 i = 0; i < eventInsurerList.length; i++) {
            address insurer = eventInsurerList[i];
            if (insurers[insurer].isActive) {
                totalCapital += insurers[insurer].eventAllocations[eventId];
            }
        }
        
        for (uint256 i = 0; i < eventInsurerList.length; i++) {
            address insurer = eventInsurerList[i];
            if (insurers[insurer].isActive) {
                uint256 allocation = insurers[insurer].eventAllocations[eventId];
                if (allocation > 0) {
                    uint256 share = (amount * allocation) / totalCapital;
                    insurers[insurer].consumedCapital += share;
                    insurers[insurer].eventAllocations[eventId] -= share;
                    emit CapitalConsumed(insurer, share);
                }
            }
        }
        
        events[eventId].totalInsurerCapital -= amount;
    }

    /**
     * @dev Consume reinsurer capital proportionally
     */
    function consumeReinsurerCapital(uint256 amount) internal {
        uint256 totalCapital = getTotalReinsurerCapital();
        
        for (uint256 i = 0; i < reinsurerList.length; i++) {
            address reinsurer = reinsurerList[i];
            if (reinsurers[reinsurer].isActive) {
                uint256 share = (amount * reinsurers[reinsurer].collateral) / totalCapital;
                reinsurers[reinsurer].consumedCapital += share;
                reinsurers[reinsurer].collateral -= share;
            }
        }
    }

    // View functions
    function getTotalInsurerCapital() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < insurerList.length; i++) {
            address insurer = insurerList[i];
            if (insurers[insurer].isActive) {
                total += insurers[insurer].totalCollateral;
            }
        }
        return total;
    }

    function getTotalReinsurerCapital() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < reinsurerList.length; i++) {
            address reinsurer = reinsurerList[i];
            if (reinsurers[reinsurer].isActive) {
                total += reinsurers[reinsurer].collateral;
            }
        }
        return total;
    }

    function getInsurerCount() public view returns (uint256) {
        return insurerList.length;
    }

    function getReinsurerCount() public view returns (uint256) {
        return reinsurerList.length;
    }

    function getInsurerByIndex(uint256 index) public view returns (address) {
        require(index < insurerList.length, "Index out of bounds");
        return insurerList[index];
    }

    function getReinsurerByIndex(uint256 index) public view returns (address) {
        require(index < reinsurerList.length, "Index out of bounds");
        return reinsurerList[index];
    }

    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        return policies[policyId];
    }

    function getEvent(uint256 eventId) external view returns (Event memory) {
        return events[eventId];
    }

    /**
     * @dev Get insurer's allocation for a specific event
     */
    function getInsurerEventAllocation(address insurer, uint256 eventId) external view returns (uint256) {
        return insurers[insurer].eventAllocations[eventId];
    }

    /**
     * @dev Get all events an insurer has allocated to
     */
    function getInsurerAllocatedEvents(address insurer) external view returns (uint256[] memory) {
        return insurers[insurer].allocatedEvents;
    }

    /**
     * @dev Get all insurers for a specific event
     */
    function getEventInsurers(uint256 eventId) external view returns (address[] memory) {
        return eventInsurers[eventId];
    }

    /**
     * @dev Get total capital allocated to a specific event
     */
    function getEventTotalInsurerCapital(uint256 eventId) external view returns (uint256) {
        return events[eventId].totalInsurerCapital;
    }

    /**
     * @dev Get accumulated premiums for an insurer
     */
    function getInsurerAccumulatedPremiums(address insurer) external view returns (uint256) {
        return insurers[insurer].accumulatedPremiums;
    }

    /**
     * @dev Get accumulated premiums for a reinsurer
     */
    function getReinsurerAccumulatedPremiums(address reinsurer) external view returns (uint256) {
        return reinsurers[reinsurer].accumulatedPremiums;
    }

    /**
     * @dev Check if there are accumulated premiums ready for distribution
     */
    function hasAccumulatedPremiums() external view returns (bool) {
        for (uint256 eventId = 1; eventId <= _eventIds.current(); eventId++) {
            Event storage eventData = events[eventId];
            if (eventData.isActive && !eventData.isTriggered && eventData.accumulatedPremiums > 0) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get total accumulated premiums across all events
     */
    function getTotalAccumulatedPremiums() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 eventId = 1; eventId <= _eventIds.current(); eventId++) {
            Event storage eventData = events[eventId];
            if (eventData.isActive && !eventData.isTriggered) {
                total += eventData.accumulatedPremiums;
            }
        }
        return total;
    }
} 