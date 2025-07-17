// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InsurancePolicyHolder.sol";
import "./InsuranceEvents.sol";
import { IInsurancePolicyHolder } from "./InsurancePolicyHolder.sol";

contract InsuranceInsurer {
    IERC20 public paymentToken;
    struct Insurer {
        uint256 totalCollateral;
        uint256 availableCollateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
        mapping(uint256 => uint256) eventAllocations; // eventId => amount
    }
    mapping(address => Insurer) public insurers;
    address[] public insurerList;
    event InsurerRegistered(address indexed insurer, uint256 collateral);
    event InsurerCapitalAdded(address indexed insurer, uint256 amount);
    event CapitalAllocated(address indexed insurer, uint256 eventId, uint256 amount);

    uint256 public constant MIN_COLLATERAL = 1000 ether;

    IInsurancePolicyHolder public policyHolder;
    InsuranceEvents public eventsLogic;
    address public core;

    constructor(address _paymentToken, address _policyHolder) {
        paymentToken = IERC20(_paymentToken);
        policyHolder = IInsurancePolicyHolder(_policyHolder);
    }

    /**
     * @dev Register an insurer with virtual collateral (no actual ERC20 transfer)
     * @param insurerAddr Address of the insurer to register
     * @param collateral Amount of collateral (already transferred virtually in InsuranceCore)
     */
    function registerInsurer(address insurerAddr, uint256 collateral) external {
        require(!insurers[insurerAddr].isActive, "Already registered");
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        
        // No actual transfer needed - virtual transfer already done in InsuranceCore
        Insurer storage ins = insurers[insurerAddr];
        ins.totalCollateral = collateral;
        ins.availableCollateral = collateral;
        ins.consumedCapital = 0;
        ins.totalPremiums = 0;
        ins.isActive = true;
        insurerList.push(insurerAddr);
        // eventAllocations mapping is left as default (empty)
        emit InsurerRegistered(insurerAddr, collateral);
    }

    /**
     * @dev Add additional capital to an existing insurer (virtual transfer)
     * @param insurerAddr Address of the insurer to add capital to
     * @param amount Amount to add (will be handled by InsuranceCore)
     */
    function addInsurerCapital(address insurerAddr, uint256 amount) external {
        require(insurers[insurerAddr].isActive, "Not registered");
        require(amount > 0, "Amount must be greater than 0");
        
        // Virtual transfer handled by InsuranceCore
        insurers[insurerAddr].totalCollateral += amount;
        insurers[insurerAddr].availableCollateral += amount;
        emit InsurerCapitalAdded(insurerAddr, amount);
    }

    function allocateToEvent(address insurerAddr, uint256 eventId, uint256 amount) external {
        require(insurers[insurerAddr].isActive, "Not registered");
        require(insurers[insurerAddr].availableCollateral >= amount, "Insufficient collateral");
        insurers[insurerAddr].availableCollateral -= amount;
        insurers[insurerAddr].eventAllocations[eventId] += amount; // Store allocation
        emit CapitalAllocated(insurerAddr, eventId, amount);
        // Update total insurer capital in PolicyHolder
        uint256 total = getEventTotalInsurerCapital(eventId);
        policyHolder.setEventInsurerCapital(eventId, total);
    }

    function removeFromEvent(address insurerAddr, uint256 eventId, uint256 amount) external {
        // Implement logic as needed, using insurerAddr
    }

    function claimInsurerPremiums() external {
        // Implement logic to claim premiums
    }

    function getInsurerEventAllocation(address insurerAddr, uint256 eventId) external view returns (uint256) {
        return insurers[insurerAddr].eventAllocations[eventId];
    }

    function getInsurerAllocatedEvents(address insurerAddr) external view returns (uint256[] memory) {
        // Implement logic to get allocated events
        return new uint256[](0);
    }

    function getEventInsurers(uint256 eventId) external view returns (address[] memory) {
        // Implement logic to get insurers for an event
        return new address[](0);
    }

    function getEventTotalInsurerCapital(uint256 eventId) public view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < insurerList.length; i++) {
            total += insurers[insurerList[i]].eventAllocations[eventId];
        }
        return total;
    }

    function getInsurerAccumulatedPremiums(address insurerAddr) external view returns (uint256) {
        // Implement logic to get accumulated premiums
        return 0;
    }

    function getInsurerCount() external view returns (uint256) {
        // Implement logic to get insurer count
        return 0;
    }

    function setCore(address _core) external {
        core = _core;
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
        // Payout is now handled by InsuranceCore
        require(core != address(0), "Core not set");
        (bool ok, ) = core.call(abi.encodeWithSignature("processClaim(address,uint256,uint256)", holder, policyId, coverage));
        require(ok, "Claim payout failed");
        // Mark as claimed
        policyHolder.markPolicyClaimed(policyId);
    }

    function setPolicyHolder(address _policyHolder) external {
        policyHolder = IInsurancePolicyHolder(_policyHolder);
    }

    function setEventsLogic(address _eventsLogic) external {
        eventsLogic = InsuranceEvents(_eventsLogic);
    }

    /**
     * @dev Check if an address is registered as an insurer
     * @param insurerAddr Address to check
     * @return isActive True if the address is an active insurer
     */
    function isRegisteredInsurer(address insurerAddr) external view returns (bool isActive) {
        return insurers[insurerAddr].isActive;
    }
}

interface IInsuranceInsurer {
    function registerInsurer(address insurerAddr, uint256 collateral) external;
    function addInsurerCapital(address insurerAddr, uint256 amount) external;
    function allocateToEvent(address insurerAddr, uint256 eventId, uint256 amount) external;
    function removeFromEvent(address insurerAddr, uint256 eventId, uint256 amount) external;
    function claimInsurerPremiums() external;
    function getInsurerEventAllocation(address insurerAddr, uint256 eventId) external view returns (uint256);
    function getInsurerAllocatedEvents(address insurerAddr) external view returns (uint256[] memory);
    function getEventInsurers(uint256 eventId) external view returns (address[] memory);
    function getEventTotalInsurerCapital(uint256 eventId) external view returns (uint256);
    function getInsurerAccumulatedPremiums(address insurerAddr) external view returns (uint256);
    function getInsurerCount() external view returns (uint256);
    function isRegisteredInsurer(address insurerAddr) external view returns (bool isActive);
} 