// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InsurancePolicyHolder.sol";
import "./InsuranceEvents.sol";

contract InsuranceInsurer {
    IERC20 public paymentToken;
    struct Insurer {
        uint256 totalCollateral;
        uint256 availableCollateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
    }
    mapping(address => Insurer) public insurers;
    event InsurerRegistered(address indexed insurer, uint256 collateral);
    event InsurerCapitalAdded(address indexed insurer, uint256 amount);
    event CapitalAllocated(address indexed insurer, uint256 eventId, uint256 amount);

    uint256 public constant MIN_COLLATERAL = 1000 ether;

    InsurancePolicyHolder public policyHolder;
    InsuranceEvents public eventsLogic;

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    function registerInsurer(uint256 collateral) external {
        require(!insurers[msg.sender].isActive, "Already registered");
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        paymentToken.transferFrom(msg.sender, address(this), collateral);
        insurers[msg.sender] = Insurer({
            totalCollateral: collateral,
            availableCollateral: collateral,
            consumedCapital: 0,
            totalPremiums: 0,
            isActive: true
        });
        emit InsurerRegistered(msg.sender, collateral);
    }

    function addInsurerCapital(uint256 amount) external {
        require(insurers[msg.sender].isActive, "Not registered");
        paymentToken.transferFrom(msg.sender, address(this), amount);
        insurers[msg.sender].totalCollateral += amount;
        insurers[msg.sender].availableCollateral += amount;
        emit InsurerCapitalAdded(msg.sender, amount);
    }

    function allocateToEvent(uint256 eventId, uint256 amount) external {
        require(insurers[msg.sender].isActive, "Not registered");
        require(insurers[msg.sender].availableCollateral >= amount, "Insufficient collateral");
        insurers[msg.sender].availableCollateral -= amount;
        // Allocation logic would go here (event mapping, etc.)
        emit CapitalAllocated(msg.sender, eventId, amount);
    }

    function claimPolicy(uint256 policyId) external {
        // Get policy info
        (address holder, uint256 eventId, uint256 coverage, , , , bool isActive, bool isClaimed) = policyHolder.getPolicy(policyId);
        require(holder == msg.sender, "Not policy holder");
        require(isActive, "Policy not active");
        require(!isClaimed, "Already claimed");
        // Check event is triggered
        (,,,bool isTriggered,,,,,,,,) = eventsLogic.getEvent(eventId);
        require(isTriggered, "Event not triggered");
        // Payout
        paymentToken.transfer(holder, coverage);
        // Mark as claimed
        policyHolder.markPolicyClaimed(policyId);
    }

    function setPolicyHolder(address _policyHolder) external {
        policyHolder = InsurancePolicyHolder(_policyHolder);
    }

    function setEventsLogic(address _eventsLogic) external {
        eventsLogic = InsuranceEvents(_eventsLogic);
    }
}

interface IInsuranceInsurer {
    function registerInsurer(uint256 collateral) external;
    function addInsurerCapital(uint256 amount) external;
    function allocateToEvent(uint256 eventId, uint256 amount) external;
    function removeFromEvent(uint256 eventId, uint256 amount) external;
    function claimInsurerPremiums() external;
    function getInsurerEventAllocation(address insurerAddr, uint256 eventId) external view returns (uint256);
    function getInsurerAllocatedEvents(address insurerAddr) external view returns (uint256[] memory);
    function getEventInsurers(uint256 eventId) external view returns (address[] memory);
    function getEventTotalInsurerCapital(uint256 eventId) external view returns (uint256);
    function getInsurerAccumulatedPremiums(address insurerAddr) external view returns (uint256);
    function getInsurerCount() external view returns (uint256);
} 