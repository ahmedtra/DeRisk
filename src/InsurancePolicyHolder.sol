// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./InsuranceEvents.sol";

contract InsurancePolicyHolder {
    using Counters for Counters.Counter;

    IERC20 public paymentToken;
    uint256 public LOCKUP_PERIOD = 7 days;
    Counters.Counter private _policyIds;

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
    mapping(uint256 => Policy) public policies;
    event PolicyCreated(uint256 indexed policyId, address indexed policyHolder, uint256 indexed eventId, uint256 premium, uint256 coverage);
    event PolicyActivated(uint256 indexed policyId, uint256 activationTime);
    event PolicyClaimed(uint256 indexed policyId, uint256 payout);

    InsuranceEvents public eventsLogic;
    mapping(uint256 => uint256) public eventInsurerCapital; // eventId => total insurer capital (stub for now)

    address public insurer;
    function setInsurer(address _insurer) external {
        insurer = _insurer;
    }

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    function setEventsLogic(address _eventsLogic) external {
        eventsLogic = InsuranceEvents(_eventsLogic);
    }

    function buyPolicy(address policyHolderAddr, uint256 eventId, uint256 coverage, uint256 premium) external {
        // Check event exists and is active
        (string memory name,,,,,,,,bool isActive,,,) = eventsLogic.getEvent(eventId);
        require(bytes(name).length != 0, "Event does not exist");
        require(isActive, "Event not active");
        // Check insurer capital
        require(eventInsurerCapital[eventId] > 0, "No insurer capital for event");
        require(coverage > 0, "Coverage must be > 0");
        require(premium > 0, "Premium must be > 0");
        
        // For virtual token management, we need to check if the user has sufficient balance
        // This will be handled by the InsuranceCore contract calling this function
        // The actual token transfer is handled at the InsuranceCore level
        
        _policyIds.increment();
        uint256 policyId = _policyIds.current();
        policies[policyId] = Policy({
            policyHolder: policyHolderAddr,
            eventId: eventId,
            coverage: coverage,
            premium: premium,
            startTime: block.timestamp,
            activationTime: block.timestamp + LOCKUP_PERIOD,
            isActive: false,
            isClaimed: false
        });
        emit PolicyCreated(policyId, policyHolderAddr, eventId, premium, coverage);
    }

    function activatePolicy(address policyHolderAddr, uint256 policyId) external {
        Policy storage policy = policies[policyId];
        require(policy.policyHolder == policyHolderAddr, "Not policy holder");
        require(block.timestamp >= policy.activationTime, "Lockup not expired");
        require(!policy.isActive, "Already active");
        policy.isActive = true;
        emit PolicyActivated(policyId, block.timestamp);
    }

    function getPolicy(uint256 policyId) external view returns (
        address policyHolder_,
        uint256 eventId,
        uint256 coverage,
        uint256 premium,
        uint256 startTime,
        uint256 activationTime,
        bool isActive,
        bool isClaimed
    ) {
        Policy storage p = policies[policyId];
        return (
            p.policyHolder,
            p.eventId,
            p.coverage,
            p.premium,
            p.startTime,
            p.activationTime,
            p.isActive,
            p.isClaimed
        );
    }

    function setEventInsurerCapital(uint256 eventId, uint256 amount) external {
        eventInsurerCapital[eventId] = amount;
    }

    function claimPolicy(uint256 policyId) external {
        Policy storage policy = policies[policyId];
        require(policy.policyHolder == msg.sender, "Not policy holder");
        require(policy.isActive, "Policy not active");
        require(!policy.isClaimed, "Already claimed");
        (,,,bool isTriggered,,,,,,,,) = eventsLogic.getEvent(policy.eventId);
        require(isTriggered, "Event not triggered");
        // No payout here. Insurer will handle payout and marking as claimed.
    }

    function markPolicyClaimed(uint256 policyId) external {
        require(msg.sender == insurer, "Only insurer can mark claimed");
        Policy storage policy = policies[policyId];
        require(!policy.isClaimed, "Already claimed");
        policy.isClaimed = true;
        emit PolicyClaimed(policyId, policy.coverage);
    }
}

// Interface for InsuranceCore to interact with
interface IInsurancePolicyHolder {
    function buyPolicy(address policyHolderAddr, uint256 eventId, uint256 coverage, uint256 premium) external;
    function activatePolicy(address policyHolderAddr, uint256 policyId) external;
    function getPolicy(uint256 policyId) external view returns (
        address policyHolder_,
        uint256 eventId,
        uint256 coverage,
        uint256 premium,
        uint256 startTime,
        uint256 activationTime,
        bool isActive,
        bool isClaimed
    );
} 