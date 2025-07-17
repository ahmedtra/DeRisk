// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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
 * - Virtual token management for efficient cross-contract operations
 */
contract InsuranceCore is InsuranceStorage, Ownable, ReentrancyGuard {

    
    // All state variables and constants have been moved to InsuranceStorage.sol
    // Do not redeclare them here.

    IInsurancePolicyHolder public policyHolder;
    IInsuranceInsurer public insurer;
    IInsuranceReinsurer public reinsurer;
    IInsuranceEvents public eventsLogic;

    constructor(address _paymentToken, address _policyHolder, address _insurer, address _reinsurer, address _eventsLogic) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentToken);
        policyHolder = IInsurancePolicyHolder(_policyHolder);
        insurer = IInsuranceInsurer(_insurer);
        reinsurer = IInsuranceReinsurer(_reinsurer);
        eventsLogic = IInsuranceEvents(_eventsLogic);
    }

    // --- Virtual Token Management Functions ---

    /**
     * @dev Deposit tokens into the system for virtual management
     * @param amount Amount of tokens to deposit
     */
    function depositTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(paymentToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        userBalances[msg.sender] += amount;
        totalSystemLiquidity += amount;
        
        emit TokensDeposited(msg.sender, amount);
    }

    /**
     * @dev Withdraw tokens from user's virtual balance
     * @param amount Amount of tokens to withdraw
     */
    function withdrawTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        
        userBalances[msg.sender] -= amount;
        totalSystemLiquidity -= amount;
        
        require(paymentToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit TokensWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Get user's total available balance (deposited - locked in roles)
     */
    function getUserBalance(address user) external view returns (uint256) {
        return userBalances[user];
    }

    /**
     * @dev Get user's total locked collateral across all roles
     */
    function getUserLockedCollateral(address user) external view returns (uint256) {
        return insurerCollateral[user] + reinsurerCollateral[user] + policyHolderFunds[user];
    }

    // --- Only interface calls to eventsLogic and coordination logic below ---

    // Register a new insurance event
    function registerEvent(
        string memory name,
        string memory description,
        uint256 triggerThreshold,
        uint256 basePremium
    ) external {
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
    function buyPolicy(uint256 eventId, uint256 coverage, uint256 premium) external nonReentrant {
        require(userBalances[msg.sender] >= premium, "Insufficient balance");
        
        // Virtual transfer: move tokens from user balance to policy holder funds
        userBalances[msg.sender] -= premium;
        policyHolderFunds[msg.sender] += premium;
        
        // Call the policy holder contract
        policyHolder.buyPolicy(msg.sender, eventId, coverage, premium);
    }
    function activatePolicy(uint256 policyId) external {
        policyHolder.activatePolicy(msg.sender, policyId);
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

    // Insurer functions - Updated for virtual token management
    function registerInsurer(uint256 collateral) external nonReentrant {
        require(userBalances[msg.sender] >= collateral, "Insufficient balance");
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        
        // Virtual transfer: move tokens from user balance to insurer collateral
        userBalances[msg.sender] -= collateral;
        insurerCollateral[msg.sender] += collateral;
        
        // Register in InsuranceInsurer contract
        insurer.registerInsurer(msg.sender, collateral);
        
        emit InsurerRegistered(msg.sender, collateral);
    }

    function allocateToEvent(uint256 eventId, uint256 amount) external {
        insurer.allocateToEvent(msg.sender, eventId, amount);
    }
    function removeFromEvent(uint256 eventId, uint256 amount) external {
        insurer.removeFromEvent(msg.sender, eventId, amount);
    }
    function addInsurerCapital(uint256 amount) external nonReentrant {
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        
        // Check if user is registered as insurer through the InsuranceInsurer contract
        require(insurer.isRegisteredInsurer(msg.sender), "Not registered as insurer");
        
        // Virtual transfer: move tokens from user balance to insurer collateral
        userBalances[msg.sender] -= amount;
        insurerCollateral[msg.sender] += amount;
        
        // Update the insurer contract
        insurer.addInsurerCapital(msg.sender, amount);
        
        emit InsurerCapitalAdded(msg.sender, amount);
    }
    function claimInsurerPremiums() external {
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

    // Reinsurer functions - Updated for virtual token management
    function registerReinsurer(uint256 collateral) external nonReentrant {
        require(userBalances[msg.sender] >= collateral, "Insufficient balance");
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        
        // Virtual transfer: move tokens from user balance to reinsurer collateral
        userBalances[msg.sender] -= collateral;
        reinsurerCollateral[msg.sender] += collateral;
        
        // Register in InsuranceReinsurer contract
        reinsurer.registerReinsurer(msg.sender, collateral);
        
        emit ReinsurerRegistered(msg.sender, collateral);
    }

    function claimReinsurerPremiums() external {
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

    // Events
    event TokensDeposited(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);
    event InsurerRegistered(address indexed insurer, uint256 collateral);
    event ReinsurerRegistered(address indexed reinsurer, uint256 collateral);
    event InsurerCapitalAdded(address indexed insurer, uint256 amount);

    /**
     * @dev Process a claim payout (called by InsuranceInsurer)
     */
    function processClaim(address policyHolderAddr, uint256 policyId, uint256 payout) external nonReentrant {
        require(msg.sender == address(insurer), "Only insurer can process claim");
        require(payout > 0, "Payout must be > 0");
        // Optionally, check policy is not already claimed (for extra safety)
        (,,,,,,,bool isClaimed) = policyHolder.getPolicy(policyId);
        require(!isClaimed, "Policy already claimed");
        // Credit payout to user's virtual balance
        userBalances[policyHolderAddr] += payout;
        // Optionally, deduct from insurer collateral (not implemented here, but can be added)
        emit ClaimProcessed(policyHolderAddr, policyId, payout);
    }
    event ClaimProcessed(address indexed policyHolder, uint256 indexed policyId, uint256 payout);

    function getEventCount() public view returns (uint256) {
        return IInsuranceEvents(eventsLogic).getEventCount();
    }
} 