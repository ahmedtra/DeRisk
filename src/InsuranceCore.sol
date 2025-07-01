// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./InsuranceStorage.sol";
import "./InsuranceEvents.sol";
import "./InsuranceInsurer.sol";
import "./InsuranceReinsurer.sol";
import "./InsurancePolicyHolder.sol";

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
contract InsuranceCore is Ownable {
    using Counters for Counters.Counter;
    
    // All state variables and constants have been moved to InsuranceStorage.sol
    // Do not redeclare them here.

    IInsurancePolicyHolder public policyHolder;
    IInsuranceInsurer public insurer;
    IInsuranceReinsurer public reinsurer;
    IInsuranceEvents public eventsLogic;

    constructor(address _policyHolder, address _insurer, address _reinsurer, address _eventsLogic) {
        policyHolder = IInsurancePolicyHolder(_policyHolder);
        insurer = IInsuranceInsurer(_insurer);
        reinsurer = IInsuranceReinsurer(_reinsurer);
        eventsLogic = IInsuranceEvents(_eventsLogic);
    }

    // --- Only interface calls to eventsLogic and coordination logic below ---

    // Register a new insurance event
    function registerEvent(
        string memory name,
        string memory description,
        uint256 triggerThreshold,
        uint256 basePremium
    ) external onlyOwner {
        eventsLogic.registerEvent(name, description, triggerThreshold, basePremium);
    }

    // Get event details via interface
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
        return eventsLogic.getEvent(eventId);
    }

    // Policy functions
    function buyPolicy(uint256 eventId, uint256 coverage, uint256 premium) external onlyOwner {
        policyHolder.buyPolicy(eventId, coverage, premium);
    }
    function activatePolicy(uint256 policyId) external {
        policyHolder.activatePolicy(policyId);
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
        return policyHolder.getPolicy(policyId);
    }

    // Insurer functions
    function registerInsurer(uint256 collateral) external onlyOwner {
        insurer.registerInsurer(collateral);
    }
    function allocateToEvent(uint256 eventId, uint256 amount) external onlyOwner {
        insurer.allocateToEvent(eventId, amount);
    }
    function removeFromEvent(uint256 eventId, uint256 amount) external onlyOwner {
        insurer.removeFromEvent(eventId, amount);
    }
    function claimInsurerPremiums() external onlyOwner {
        insurer.claimInsurerPremiums();
    }
    function getInsurerEventAllocation(address insurerAddr, uint256 eventId) external view returns (uint256) {
        return insurer.getInsurerEventAllocation(insurerAddr, eventId);
    }
    function getInsurerAllocatedEvents(address insurerAddr) external view returns (uint256[] memory) {
        return insurer.getInsurerAllocatedEvents(insurerAddr);
    }
    function getEventInsurers(uint256 eventId) external view returns (address[] memory) {
        return insurer.getEventInsurers(eventId);
    }
    function getEventTotalInsurerCapital(uint256 eventId) external view returns (uint256) {
        return insurer.getEventTotalInsurerCapital(eventId);
    }
    function getInsurerAccumulatedPremiums(address insurerAddr) external view returns (uint256) {
        return insurer.getInsurerAccumulatedPremiums(insurerAddr);
    }

    // Reinsurer functions
    function registerReinsurer(uint256 collateral) external onlyOwner {
        reinsurer.registerReinsurer(collateral);
    }
    function claimReinsurerPremiums() external onlyOwner {
        reinsurer.claimReinsurerPremiums();
    }
    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256) {
        return reinsurer.getReinsurerAccumulatedPremiums(reinsurerAddr);
    }
    function getTotalReinsurerCapital() public view returns (uint256) {
        return reinsurer.getTotalReinsurerCapital();
    }
    function getReinsurerCount() public view returns (uint256) {
        return reinsurer.getReinsurerCount();
    }
    function getInsurerCount() public view returns (uint256) {
        return insurer.getInsurerCount();
    }
    function getReinsurerByIndex(uint256 index) public view returns (address) {
        return reinsurer.getReinsurerByIndex(index);
    }

    // Premium distribution
    function triggerPremiumDistribution() external {
        eventsLogic.triggerPremiumDistribution();
    }
    function distributeAccumulatedPremiums() external {
        eventsLogic.distributeAccumulatedPremiums();
    }
    function hasAccumulatedPremiums() external view returns (bool) {
        return eventsLogic.hasAccumulatedPremiums();
    }
    function getTotalAccumulatedPremiums() external view returns (uint256) {
        return eventsLogic.getTotalAccumulatedPremiums();
    }

    // Event trigger
    function triggerEvent(uint256 eventId) external onlyOwner {
        eventsLogic.triggerEvent(eventId);
    }

    // Premium calculation
    function calculatePremium(uint256 eventId, uint256 coverage) external view returns (uint256) {
        return eventsLogic.calculatePremium(eventId, coverage);
    }
} 