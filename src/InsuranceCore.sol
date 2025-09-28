// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/console2.sol";
import "./InsuranceStorage.sol";
import "./InsuranceEvents.sol";
import "./InsuranceInsurer.sol";
import "./InsuranceReinsurer.sol";
import "./IInsuranceReinsurer.sol";
import "./InsurancePolicyHolder.sol";
import "./InsuranceReinsuranceMath.sol";

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
    InsuranceReinsuranceMath public reinsuranceMath;
    
    // Track last policy purchase time for each event to calculate time-based premiums

    
    // Track last premium collection time for each policy
    mapping(uint256 => uint256) public policyLastPremiumCollection;

    constructor(address _paymentToken, address _policyHolder, address _insurer, address _reinsurer, address _eventsLogic, address _reinsuranceMath) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentToken);
        policyHolder = IInsurancePolicyHolder(_policyHolder);
        insurer = IInsuranceInsurer(_insurer);
        reinsurer = IInsuranceReinsurer(_reinsurer);
        eventsLogic = IInsuranceEvents(_eventsLogic);
        reinsuranceMath = InsuranceReinsuranceMath(_reinsuranceMath);
        
        // Set the core address in the insurer and reinsurer contracts
        insurer.setCore(address(this));
        reinsurer.setCore(address(this));
        
        // Initialize reinsurance data with default values
        initializeReinsuranceData();
    }
    
    /**
     * @dev Initialize reinsurance data with default values
     * This ensures the premium calculation functions work properly
     */
    function initializeReinsuranceData() internal {
        // Set initial reinsurance data
        // These values will be updated as insurers and reinsurers register
        reinsuranceMath.updateReinsuranceData(
            1000 * 1e18, // 1000 tokens total capital
            500 * 1e18,  // 500 tokens reinsurance capital
            100 * 1e18,  // 100 tokens expected reinsurance loss
            200 * 1e18   // 200 tokens total expected loss
        );
    }

    /**
     * @dev Update reinsurance data based on current system state
     * This should be called whenever insurer or reinsurer capital changes
     */
    function updateReinsuranceData() internal {
        // Get current system state
        uint256 totalInsurerCapital = insurer.getTotalInsurerCapital();
        uint256 totalReinsurerCapital = reinsurer.getTotalReinsurerCapital();
        uint256 totalCapital = totalInsurerCapital + totalReinsurerCapital;
        
        // Calculate total coverage across all events to assess risk
        uint256 totalCoverage = 0;
        uint256 eventCount = getEventCount();
        for (uint256 i = 1; i <= eventCount; i++) {
            totalCoverage += eventsLogic.getEventTotalCoverage(i);
        }
        
        // Calculate expected losses based on coverage and capital ratios
        uint256 expectedReinsuranceLoss = totalCoverage > 0 ? 
            (totalCoverage * totalReinsurerCapital) / totalCapital : 100 * 1e18;
        uint256 totalExpectedLoss = totalCoverage > 0 ? 
            (totalCoverage * 2000) / 10000 : 200 * 1e18; // Assume 20% default loss ratio
        
        // Update reinsurance data with actual current values
        reinsuranceMath.updateReinsuranceData(
            totalCapital,
            totalReinsurerCapital,
            expectedReinsuranceLoss,
            totalExpectedLoss
        );
    }
    
    /**
     * @dev Update reinsurance data when insurer capital changes
     */
    function updateInsurerReinsuranceData() internal {
        updateReinsuranceData();
    }
    
    /**
     * @dev Update reinsurance data when reinsurer capital changes
     */
    function updateReinsurerReinsuranceData() internal {
        updateReinsuranceData();
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
     * @dev Withdraw tokens from user's virtual balance (alias for policyholders)
     * @param amount Amount of tokens to withdraw
     */
    function withdrawFromWallet(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        
        userBalances[msg.sender] -= amount;
        totalSystemLiquidity -= amount;
        
        require(paymentToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit TokensWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Policyholder-specific withdrawal function
     * Allows policyholders to withdraw funds from their wallet balance
     * @param amount Amount of tokens to withdraw
     */
    function withdrawPolicyholderFunds(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        
        // Check if user has any active policies that might be affected
        uint256 totalPolicies = policyHolder.getPolicyCount();
        bool hasActivePolicies = false;
        
        for (uint256 i = 1; i <= totalPolicies; i++) {
            try policyHolder.getPolicy(i) returns (
                address policyHolderAddr,
                uint256 policyEventId,
                uint256 coverage,
                uint256 premium,
                uint256 startTime,
                uint256 activationTime,
                bool isActive,
                bool isClaimed
            ) {
                if (policyHolderAddr == msg.sender && isActive && !isClaimed) {
                    hasActivePolicies = true;
                    break;
                }
            } catch {
                continue;
            }
        }
        
        // If user has active policies, ensure they maintain sufficient balance for premiums
        if (hasActivePolicies) {
            require(userBalances[msg.sender] - amount >= 1000 * 1e18, "Insufficient balance for active policies");
        }
        
        userBalances[msg.sender] -= amount;
        totalSystemLiquidity -= amount;
        
        require(paymentToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit PolicyholderFundsWithdrawn(msg.sender, amount);
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
        uint256 insurerCollateralAmount = insurer.isRegisteredInsurer(user) ? insurer.getInsurerTotalCollateral(user) : 0;
        uint256 reinsurerCollateralAmount = reinsurer.isRegisteredReinsurer(user) ? reinsurer.getReinsurerCollateral(user) : 0;
        return insurerCollateralAmount + reinsurerCollateralAmount + policyHolderFunds[user];
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
        
        // Update reinsurance data to reflect new event
        updateReinsuranceData();
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
    function buyPolicy(uint256 eventId, uint256 coverage, uint256 maxLossLimit) external nonReentrant {
        require(userBalances[msg.sender] >= maxLossLimit, "Insufficient balance");
        
        // Get event data to calculate dynamic annualized premium rate
        (,,,,,,,,,uint256 totalInsurerCapital,,) = eventsLogic.getEvent(eventId);
        
        // Calculate dynamic annualized premium rate using reinsurance math
        uint256 annualizedPremiumRate = calculateDynamicPremium(eventId, coverage, totalInsurerCapital);
        
        // Call the policy holder contract with the full annualized premium rate
        // The policy should represent the total annual premium commitment
        policyHolder.buyPolicy(msg.sender, eventId, coverage, annualizedPremiumRate);
        eventsLogic.addCoverage(eventId, coverage);
        
        // Update reinsurance data to reflect new policy coverage
        updateReinsuranceData();
        
        emit PolicyPremiumCalculated(msg.sender, eventId, coverage, annualizedPremiumRate);
    }
    
    /**
     * @dev Calculate dynamic premium using reinsurance math
     * This function automatically calculates the optimal premium based on:
     * - Event risk parameters
     * - Insurer capital allocation
     * - Reinsurer capital
     * - Policy coverage amount
     */
    function calculateDynamicPremium(uint256 eventId, uint256 coverage, uint256 totalInsurerCapital) internal returns (uint256) {
        // Get reinsurance data
        InsuranceReinsuranceMath.ReinsuranceData memory reinsurance = reinsuranceMath.getReinsuranceData();
        
        if (reinsurance.totalCapital == 0 || reinsurance.reinsuranceCapital == 0) {
            return 0; // Return 0 to use fallback premium
        }
        
        // Get event risk parameters - we'll use default values for now since the mapping functions aren't in the interface
        uint256 expectedLossRatio = 1000; // 10% default
        uint256 totalLossRatio = 2000; // 20% default
        
        // Calculate beta for this event based on insurer capital allocation
        uint256 beta = totalInsurerCapital > 0 ? (totalInsurerCapital * 10000) / reinsurance.totalCapital : 5000; // Default 50%
        
        // Solve for event probability and max premium
        (uint256 eventProbability, uint256 maxPremium) = reinsuranceMath.solveForEventProbabilityAndMaxPremium(
            totalInsurerCapital,
            coverage,
            beta,
            expectedLossRatio,
            totalLossRatio,
            reinsurance.reinsuranceCapital,
            reinsurance.totalCapital
        );
        
        
        // Update event risk parameters for future calculations
        eventsLogic.updateEventRiskParameters(eventId, expectedLossRatio, totalLossRatio, maxPremium);
        
        return maxPremium;
    }
    

    
    /**
     * @dev Collect ongoing premiums from all existing policyholders for a specific event
     * This function can be called periodically (e.g., monthly) to collect ongoing premiums
     * @param eventId The event ID to collect premiums for
     */
    function collectOngoingPremiumsFromAllPolicyholders(uint256 eventId) external {
        // Get the total number of policies for this event
        uint256 totalPolicies = policyHolder.getPolicyCount();
        uint256 totalCollectedPremiums = 0;
        
        // For debugging, let's just collect a fixed amount from each policyholder
        // This is a simplified version to test the concept
        for (uint256 policyId = 1; policyId <= totalPolicies; policyId++) {
            try policyHolder.getPolicy(policyId) returns (
                address policyHolderAddr,
                uint256 policyEventId,
                uint256 coverage,
                uint256 premium,
                uint256 startTime,
                uint256 activationTime,
                bool isActive,
                bool isClaimed
            ) {
                // Only process policies for this event that are active and not claimed
                if (policyEventId == eventId && isActive && !isClaimed) {
                    // Calculate time since last premium collection for this policy
                    uint256 lastCollectionTime = policyLastPremiumCollection[policyId];
                    uint256 currentTime = block.timestamp;
                    uint256 timeSinceLastCollection = lastCollectionTime == 0 ? startTime : lastCollectionTime;
                    uint256 timeElapsed = currentTime - timeSinceLastCollection;
                    
                    if (timeElapsed > 0) {
                        // Calculate premium for this policy based on time elapsed and coverage
                        // The premium stored in the policy is the annualized premium amount
                        // We need to calculate the time-based portion of that annual premium
                        uint256 annualizedPremium = premium;
                        uint256 premiumPerSecond = annualizedPremium / (365 * 24 * 3600); // Convert annual to per-second
                        uint256 policyPremium = premiumPerSecond * timeElapsed;
                        
                        // Ensure the policyholder has enough balance and premium is reasonable
                        if (userBalances[policyHolderAddr] >= policyPremium && policyPremium > 0) {
                            // Collect premium from policyholder
                            userBalances[policyHolderAddr] -= policyPremium;
                            policyHolderFunds[policyHolderAddr] += policyPremium;
                            
                            // Update last collection time for this policy
                            policyLastPremiumCollection[policyId] = currentTime;
                            
                            totalCollectedPremiums += policyPremium;
                            
                            emit PolicyholderPremiumCollected(policyId, policyHolderAddr, eventId, policyPremium);
                        }
                    }
                }
            } catch {
                // Policy doesn't exist, continue to next
                continue;
            }
        }
        
        // Accumulate the collected premiums for later distribution
        if (totalCollectedPremiums > 0) {
            eventsLogic.accumulatePremiums(eventId, totalCollectedPremiums);
            emit OngoingPremiumsCollected(eventId, totalCollectedPremiums);
        }
    }
    
    
    /**
     * @dev Distribute accumulated premiums for a specific event to all stakeholders
     * This function can be called by anyone to trigger premium distribution
     * @param eventId The event ID to distribute premiums for
     */
    function distributeEventPremiums(uint256 eventId) external {
        // Get the accumulated premiums for this event
        uint256 accumulatedPremiums = eventsLogic.getEventAccumulatedPremiums(eventId);
        require(accumulatedPremiums > 0, "No accumulated premiums to distribute");
        
        // Get event data for distribution calculations
        (,,,,,,,,,uint256 totalInsurerCapital,,) = eventsLogic.getEvent(eventId);
        
        // Get reinsurance data for distribution ratios
        InsuranceReinsuranceMath.ReinsuranceData memory reinsurance = reinsuranceMath.getReinsuranceData();
        
        if (reinsurance.totalCapital == 0) {
            return; // No capital to distribute to
        }
        
        // Calculate premium distribution using mathematical risk models
        // Use calculateSharedRiskPremium to determine insurer share, remainder goes to reinsurers
        
        // Calculate beta using the mathematical model from InsuranceReinsuranceMath
        // We'll use the total coverage for this event as policy notional and default values for other parameters
        uint256 totalCoverage = eventsLogic.getEventTotalCoverage(eventId);
        uint256 totalExpectedLossRatioSum = reinsuranceMath.calculateTotalExpectedLossRatioSum();
        uint256 mu = 1000; // Default expected return parameter (10%)
        
        uint256 beta = reinsuranceMath.calculateBeta(
            totalInsurerCapital,
            totalCoverage > 0 ? totalCoverage : 1000e18, // Use total coverage or default
            totalExpectedLossRatioSum > 0 ? totalExpectedLossRatioSum : 5000, // Use actual or default
            mu
        );
        
        // Calculate insurer's share using the mathematical model
        uint256 insurerShare = reinsuranceMath.calculateSharedRiskPremium(
            beta,
            reinsurance.reinsuranceCapital,
            reinsurance.totalCapital,
            accumulatedPremiums
        );
        
        // Reinsurer gets the remainder
        uint256 reinsurerShare = accumulatedPremiums - insurerShare;
        
        // Distribute to insurers based on their capital allocation to this event
        if (totalInsurerCapital > 0 && insurerShare > 0) {
            eventsLogic.accumulateInsurerPremiums(eventId, insurerShare);
            
            // Get all insurers and distribute premiums proportionally to their capital allocation
            address[] memory eventInsurers = insurer.getEventInsurers(eventId);
            if (eventInsurers.length > 0) {
                for (uint256 i = 0; i < eventInsurers.length; i++) {
                    address insurerAddr = eventInsurers[i];
                    uint256 insurerAllocation = insurer.getInsurerEventAllocation(insurerAddr, eventId);
                    
                    if (insurerAllocation > 0) {
                        // Calculate this insurer's share based on their capital allocation
                        uint256 insurerPremiumShare = (insurerShare * insurerAllocation) / totalInsurerCapital;
                        
                        // Credit the premium to the insurer's internal balance
                        userBalances[insurerAddr] += insurerPremiumShare;
                        
                        // Update the insurer's accumulated premiums in the insurer contract
                        insurer.addInsurerPremiums(insurerAddr, insurerPremiumShare);
                        
                        emit PremiumDistributed(eventId, insurerAddr, insurerPremiumShare, true);
                    }
                }
            }
        }
        
        // Distribute to reinsurers proportionally to their total capital
        if (reinsurance.reinsuranceCapital > 0 && reinsurerShare > 0) {
            eventsLogic.accumulateReinsurerPremiums(eventId, reinsurerShare);
            
            // Get all reinsurers and distribute premiums proportionally to their capital
            uint256 reinsurerCount = reinsurer.getReinsurerCount();
            if (reinsurerCount > 0) {
                for (uint256 i = 0; i < reinsurerCount; i++) {
                    address reinsurerAddr = reinsurer.getReinsurerByIndex(i);
                    if (reinsurer.isRegisteredReinsurer(reinsurerAddr)) {
                        uint256 reinsurerCollateral = reinsurer.getReinsurerCollateral(reinsurerAddr);
                        
                        if (reinsurerCollateral > 0) {
                            // Calculate this reinsurer's share based on their capital
                            uint256 reinsurerPremiumShare = (reinsurerShare * reinsurerCollateral) / reinsurance.reinsuranceCapital;
                            
                            // Credit the premium to the reinsurer's internal balance
                            userBalances[reinsurerAddr] += reinsurerPremiumShare;
                            
                            // Update the reinsurer's accumulated premiums in the reinsurer contract
                            reinsurer.addReinsurerPremiums(reinsurerAddr, reinsurerPremiumShare);
                            
                            emit PremiumDistributed(eventId, reinsurerAddr, reinsurerPremiumShare, false);
                        }
                    }
                }
            }
        }
        
        // Clear the accumulated premiums for this event
        eventsLogic.clearAccumulatedPremiums(eventId);
        
        emit EventPremiumsDistributed(eventId, accumulatedPremiums, insurerShare, reinsurerShare);
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

    // Insurer functions - Updated for separate registration fee and collateral
    function registerInsurer(uint256 initialCollateral) external nonReentrant {
        require(initialCollateral >= MIN_COLLATERAL, "Insufficient initial collateral");
        
        // Calculate total payment needed (registration fee + initial collateral)
        uint256 totalPayment = REGISTRATION_FEE + initialCollateral;
        
        // Transfer total payment from user to contract
        require(paymentToken.transferFrom(msg.sender, address(this), totalPayment), "Transfer failed");
        
        // Separate fee from collateral
        protocolFees += REGISTRATION_FEE;
        totalSystemLiquidity += totalPayment;
        
        // Register in InsuranceInsurer contract with initial collateral
        insurer.registerInsurer(msg.sender, initialCollateral);
        
        emit InsurerRegistered(msg.sender, initialCollateral);
        emit RegistrationFeePaid(msg.sender, REGISTRATION_FEE, true); // true = insurer
        updateInsurerReinsuranceData(); // Update reinsurance data after insurer registration
    }

    function allocateToEvent(uint256 eventId, uint256 amount) external {
        insurer.allocateToEvent(msg.sender, eventId, amount);
        
        // Update reinsurance data to reflect new capital allocation
        updateReinsuranceData();
    }
    function removeFromEvent(uint256 eventId, uint256 amount) external {
        insurer.removeFromEvent(msg.sender, eventId, amount);
        
        // Update reinsurance data to reflect capital removal
        updateReinsuranceData();
    }
    function addInsurerCapital(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        // Check if user is registered as insurer through the InsuranceInsurer contract
        require(insurer.isRegisteredInsurer(msg.sender), "Not registered as insurer");
        
        // Transfer tokens from user to contract for capital backing
        require(paymentToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Add to total system liquidity
        totalSystemLiquidity += amount;
        
        // Update the insurer contract
        insurer.addInsurerCapital(msg.sender, amount);
        
        emit InsurerCapitalAdded(msg.sender, amount);
        updateInsurerReinsuranceData(); // Update reinsurance data after insurer capital addition
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

    // Reinsurer functions - Updated for separate registration fee and collateral
    function registerReinsurer(uint256 initialCollateral) external nonReentrant {
        require(initialCollateral >= MIN_COLLATERAL, "Insufficient initial collateral");
        
        // Calculate total payment needed (registration fee + initial collateral)
        uint256 totalPayment = REGISTRATION_FEE + initialCollateral;
        
        // Transfer total payment from user to contract
        require(paymentToken.transferFrom(msg.sender, address(this), totalPayment), "Transfer failed");
        
        // Separate fee from collateral
        protocolFees += REGISTRATION_FEE;
        totalSystemLiquidity += totalPayment;
        
        // Register in InsuranceReinsurer contract with initial collateral
        reinsurer.registerReinsurer(msg.sender, initialCollateral);
        
        emit ReinsurerRegistered(msg.sender, initialCollateral);
        emit RegistrationFeePaid(msg.sender, REGISTRATION_FEE, false); // false = reinsurer
        updateReinsurerReinsuranceData(); // Update reinsurance data after reinsurer registration
    }

    function claimReinsurerPremiums() external {
        reinsurer.claimReinsurerPremiums();
    }
    
    function addReinsurerCapital(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        // Check if user is registered as reinsurer
        require(reinsurer.isRegisteredReinsurer(msg.sender), "Not registered as reinsurer");
        
        // Transfer tokens from user to contract for capital backing
        require(paymentToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Add to total system liquidity
        totalSystemLiquidity += amount;
        
        // Add capital in InsuranceReinsurer contract
        reinsurer.addReinsurerCapital(msg.sender, amount);
        
        emit ReinsurerCapitalAdded(msg.sender, amount);
        updateReinsurerReinsuranceData(); // Update reinsurance data after reinsurer capital addition
    }
    
    function getReinsurerCollateral(address reinsurerAddr) external view returns (uint256) {
        return reinsurer.getReinsurerCollateral(reinsurerAddr);
    }
    
    function isRegisteredReinsurer(address reinsurerAddr) external view returns (bool) {
        return reinsurer.isRegisteredReinsurer(reinsurerAddr);
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
        
        // Process payouts for all policies associated with this event
        processEventPayouts(eventId);
    }

    // Premium calculation
    function calculatePremium(uint256 eventId, uint256 coverage) external view returns (uint256) {
        // Get basic premium from events contract
        uint256 basePremium = eventsLogic.calculatePremium(eventId, coverage);
        
        // If reinsurance math is available, use advanced calculation
        if (address(reinsuranceMath) != address(0)) {
            return calculateAdvancedPremium(eventId, coverage, basePremium);
        }
        
        return basePremium;
    }
    
    /**
     * @dev Calculate premium using advanced reinsurance math
     */
    function calculateAdvancedPremium(uint256 eventId, uint256 coverage, uint256 basePremium) internal view returns (uint256) {
        // Get event risk parameters from events contract
        (uint256 expectedLossRatio, uint256 totalLossRatio, uint256 maxPremium) = eventsLogic.getEventRiskParameters(eventId);
        
        // Calculate beta for this event (using default parameters)
        uint256 mu = 1000; // 10% expected return parameter
        uint256 totalExpectedLossRatioSum = reinsuranceMath.totalExpectedLossRatioSum();
        if (totalExpectedLossRatioSum == 0) {
            totalExpectedLossRatioSum = 5000; // Default to 50% if no data
        }
        
        uint256 beta = reinsuranceMath.calculateBeta(
            coverage, // insurer capital
            coverage, // policy notional (using coverage as notional for this calculation)
            totalExpectedLossRatioSum,
            mu
        );
        
        // Check if reinsurance data is available, if not, fall back to basic calculation
        uint256 reinsuranceCapital = reinsuranceMath.getReinsuranceData().reinsuranceCapital;
        uint256 totalCapital = reinsuranceMath.getReinsuranceData().totalCapital;
        
        if (totalCapital == 0) {
            // No reinsurance data available, fall back to basic premium
            return basePremium;
        }
        
        // Use the solver to get both event probability and max premium
        (uint256 eventProbability, uint256 solvedMaxPremium) = reinsuranceMath.solveForEventProbabilityAndMaxPremium(
            coverage, // insurer capital
            coverage, // policy notional
            beta,
            expectedLossRatio,
            totalLossRatio,
            reinsuranceCapital,
            totalCapital
        );
        
        // If solver didn't converge, use the event's max premium
        if (solvedMaxPremium == 0) {
            solvedMaxPremium = maxPremium;
        }
        
        // Calculate premium using the shared risk premium formula
        uint256 premium = reinsuranceMath.calculateSharedRiskPremium(
            beta,
            solvedMaxPremium, // reinsurance capital
            solvedMaxPremium, // total capital
            solvedMaxPremium  // max premium
        );
        
        // Ensure premium is within reasonable bounds
        uint256 maxAllowedPremium = maxPremium * coverage / 1e18;
        
        // If the advanced calculation returns a reasonable value, use it
        // Otherwise fall back to base premium
        if (premium > 0 && premium <= maxAllowedPremium * 10) { // Allow up to 10x max premium
            return premium;
        } else {
            return basePremium;
        }
    }

    // Events
    event TokensDeposited(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);
    event PolicyholderFundsWithdrawn(address indexed user, uint256 amount);
    event InsurerRegistered(address indexed insurer, uint256 collateral);
    event ReinsurerRegistered(address indexed reinsurer, uint256 collateral);
    event ReinsurerCapitalAdded(address indexed reinsurer, uint256 amount);
    event InsurerCapitalAdded(address indexed insurer, uint256 amount);
    event PolicyPremiumCalculated(address indexed policyHolder, uint256 indexed eventId, uint256 coverage, uint256 premium);

    event PremiumDistributed(uint256 indexed eventId, address indexed stakeholder, uint256 amount, bool isInsurer);
    event EventPremiumsDistributed(uint256 indexed eventId, uint256 totalPremiums, uint256 insurerShare, uint256 reinsurerShare);
    event PolicyholderPremiumCollected(uint256 indexed policyId, address indexed policyHolder, uint256 indexed eventId, uint256 premium);
    event OngoingPremiumsCollected(uint256 indexed eventId, uint256 totalPremiums);
    event RegistrationFeePaid(address indexed user, uint256 fee, bool isInsurer);
    event ProtocolFeesWithdrawn(address indexed owner, uint256 amount);

    /**
     * @dev Process payouts for all policies associated with a triggered event
     * @param eventId The event ID that was triggered
     */
    function processEventPayouts(uint256 eventId) internal {
        // Get the total coverage for this event
        uint256 totalCoverage = eventsLogic.getEventTotalCoverage(eventId);
        require(totalCoverage > 0, "No coverage for this event");
        
        // Get all policies for this event
        uint256 totalPolicies = policyHolder.getPolicyCount();
        uint256 totalPayouts = 0;
        
        for (uint256 policyId = 1; policyId <= totalPolicies; policyId++) {
            try policyHolder.getPolicy(policyId) returns (
                address policyHolderAddr,
                uint256 policyEventId,
                uint256 coverage,
                uint256 premium,
                uint256 startTime,
                uint256 activationTime,
                bool isActive,
                bool isClaimed
            ) {
                // Only process policies for this event that are active and not claimed
                if (policyEventId == eventId && isActive && !isClaimed) {
                    // Calculate payout based on coverage
                    uint256 payout = coverage;
                    
                    // Ensure we have enough capital to pay out
                    require(totalPayouts + payout <= totalCoverage, "Insufficient capital for payouts");
                    
                    // Process the payout directly
                    userBalances[policyHolderAddr] += payout;
                    totalPayouts += payout;
                    
                    emit EventPayoutProcessed(eventId, policyId, policyHolderAddr, payout);
                }
            } catch {
                // Policy doesn't exist, continue to next
                continue;
            }
        }
        
        // Deduct payouts from insurer capital allocation to this event
        if (totalPayouts > 0) {
            deductPayoutsFromInsurerCapital(eventId, totalPayouts);
        }
        
        emit EventPayoutsCompleted(eventId, totalPayouts);
    }
    
    /**
     * @dev Deduct payouts from insurer capital allocation to the event
     * @param eventId The event ID
     * @param totalPayouts The total amount to deduct
     */
    function deductPayoutsFromInsurerCapital(uint256 eventId, uint256 totalPayouts) internal {
        // Get all insurers allocated to this event
        address[] memory eventInsurers = insurer.getEventInsurers(eventId);
        uint256 totalInsurerAllocation = insurer.getEventTotalInsurerCapital(eventId);
        
        require(totalInsurerAllocation >= totalPayouts, "Insufficient insurer capital");
        
        // Distribute the payout burden proportionally among insurers
        for (uint256 i = 0; i < eventInsurers.length; i++) {
            address insurerAddr = eventInsurers[i];
            uint256 insurerAllocation = insurer.getInsurerEventAllocation(insurerAddr, eventId);
            
            if (insurerAllocation > 0) {
                // Calculate this insurer's share of the payout burden
                uint256 insurerPayoutShare = (totalPayouts * insurerAllocation) / totalInsurerAllocation;
                
                // Deduct from insurer's capital allocation to this event
                insurer.removeFromEvent(insurerAddr, eventId, insurerPayoutShare);
                
                // Deduct from insurer's total collateral via contract call
                insurer.deductCapital(insurerAddr, insurerPayoutShare);
                
                emit InsurerCapitalDeducted(insurerAddr, eventId, insurerPayoutShare);
            }
        }
    }
    
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
    event EventPayoutProcessed(uint256 indexed eventId, uint256 indexed policyId, address indexed policyHolder, uint256 payout);
    event EventPayoutsCompleted(uint256 indexed eventId, uint256 totalPayouts);
    event InsurerCapitalDeducted(address indexed insurer, uint256 indexed eventId, uint256 amount);

    function getEventCount() public view returns (uint256) {
        return IInsuranceEvents(eventsLogic).getEventCount();
    }
    
    /**
     * @dev Get accumulated protocol fees from registrations
     */
    function getProtocolFees() external view returns (uint256) {
        return protocolFees;
    }
    
    /**
     * @dev Withdraw protocol fees (only owner)
     * @param amount Amount to withdraw
     */
    function withdrawProtocolFees(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= protocolFees, "Insufficient protocol fees");
        require(amount > 0, "Amount must be greater than 0");
        
        protocolFees -= amount;
        totalSystemLiquidity -= amount;
        
        require(paymentToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit ProtocolFeesWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Get registration fee constant
     */
    function getRegistrationFee() external pure returns (uint256) {
        return REGISTRATION_FEE;
    }
    
    // ==================== PERIODIC PREMIUM DISTRIBUTION ====================
    
    // Track last distribution time for each event to enforce intervals
    mapping(uint256 => uint256) public eventLastDistributionTime;
    
    // Minimum distribution interval (e.g., 1 day = 86400 seconds)
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 1 days;
    
    // Gratification percentage for the caller (0.1% = 1000 basis points)
    uint256 public constant DISTRIBUTION_GRATIFICATION_BPS = 1000; // 0.1%
    
    /**
     * @dev Distribute accumulated premiums periodically with gratification for the caller
     * @param eventId The event ID to distribute premiums for
     * @param distributionInterval The minimum time interval between distributions
     * 
     * This function can be called by anyone, but only if:
     * 1. Enough time has passed since last distribution
     * 2. There are accumulated premiums to distribute
     * 3. The distribution interval is at least the minimum required
     * 
     * The caller receives a gratification of 0.1% of the distributed premiums
     */
    function distributeAccumulatedPremiumsPeriodically(
        uint256 eventId, 
        uint256 distributionInterval
    ) external nonReentrant {
        // Validate the distribution interval
        require(distributionInterval >= MIN_DISTRIBUTION_INTERVAL, "Interval too short");
        
        // Check if enough time has passed since last distribution
        uint256 lastDistribution = eventLastDistributionTime[eventId];
        require(
            block.timestamp >= lastDistribution + distributionInterval, 
            "Too early for distribution"
        );
        
        // Get current accumulated premiums
        uint256 currentPremiums = eventsLogic.getEventAccumulatedPremiums(eventId);
        require(currentPremiums > 0, "No premiums to distribute");
        
        // Calculate gratification for the caller (0.1% of premiums)
        uint256 gratification = (currentPremiums * DISTRIBUTION_GRATIFICATION_BPS) / 100000;
        
        // Distribute the premiums (excluding gratification)
        uint256 premiumsToDistribute = currentPremiums - gratification;
        
        // Call the existing distribution logic
        _distributeEventPremiums(eventId, premiumsToDistribute);
        
        // Credit gratification to the caller
        userBalances[msg.sender] += gratification;
        
        // Update last distribution time
        eventLastDistributionTime[eventId] = block.timestamp;
        
        emit PeriodicDistributionExecuted(
            eventId, 
            msg.sender, 
            premiumsToDistribute, 
            gratification, 
            block.timestamp
        );
    }
    
    /**
     * @dev Internal function to distribute premiums (extracted from existing distributeEventPremiums)
     * @param eventId The event ID
     * @param totalPremiums The total premiums to distribute
     */
    function _distributeEventPremiums(uint256 eventId, uint256 totalPremiums) internal {
        // Get event details
        (,,,,,,,uint256 maxPremium, bool isActive,,,) = eventsLogic.getEvent(eventId);
        require(isActive, "Event is not active");

        // Distribute to insurers
        address[] memory eventInsurers = insurer.getEventInsurers(eventId);

        uint256 totalInsurerAllocation = 0;
        for (uint256 i = 0; i < eventInsurers.length; i++) {
            address insurerAddr = eventInsurers[i];
            uint256 insurerAllocation = insurer.getInsurerEventAllocation(insurerAddr, eventId);
            totalInsurerAllocation += insurerAllocation;
        }
        // Get reinsurance data
        InsuranceReinsuranceMath.ReinsuranceData memory reinsuranceData = reinsuranceMath.getReinsuranceData();
        
        // Calculate total coverage for this event
        uint256 totalCoverage = eventsLogic.getEventTotalCoverage(eventId);
        
        // Calculate beta for this event
        uint256 totalExpectedLossRatioSum = reinsuranceMath.calculateTotalExpectedLossRatioSum();
        if (totalExpectedLossRatioSum == 0) {
            totalExpectedLossRatioSum = 5000; // Default value
        }
        
        uint256 beta = reinsuranceMath.calculateBeta(
            totalInsurerAllocation,
            totalCoverage,
            totalExpectedLossRatioSum, // mu parameter
            5000  // expected loss ratio
        );
        
        // Calculate premium split between insurers and reinsurers
        uint256 insurerShare = reinsuranceMath.calculateSharedRiskPremium(
            beta,
            reinsuranceData.reinsuranceCapital,
            reinsuranceData.totalCapital,
            totalPremiums
        );
        
        // Ensure insurerShare doesn't exceed totalPremiums to prevent negative reinsurerShare
        if (insurerShare > totalPremiums) {
            insurerShare = totalPremiums;
        }
        
        uint256 reinsurerShare = totalPremiums - insurerShare;
        
        // Debug: Log reinsurance data and calculations
        console2.log("=== REINSURANCE DEBUG ===");
        console2.log("totalPremiums:", totalPremiums / 1e18);
        console2.log("insurerShare:", insurerShare / 1e18);
        console2.log("reinsurerShare:", reinsurerShare / 1e18);
        console2.log("reinsuranceData.reinsuranceCapital:", reinsuranceData.reinsuranceCapital / 1e18);
        console2.log("reinsuranceData.totalCapital:", reinsuranceData.totalCapital / 1e18);
        


        for (uint256 i = 0; i < eventInsurers.length; i++) {
            address insurerAddr = eventInsurers[i];
            uint256 insurerAllocation = insurer.getInsurerEventAllocation(insurerAddr, eventId);
            
            if (insurerAllocation > 0) {
                // Calculate proportional share based on allocation
                uint256 insurerPremiumShare = (insurerShare * insurerAllocation) / totalInsurerAllocation;
                
                // Credit insurer's internal balance
                userBalances[insurerAddr] += insurerPremiumShare;
                
                // Update insurer's total premiums
                insurer.addInsurerPremiums(insurerAddr, insurerPremiumShare);
                
                emit PremiumDistributed(eventId, insurerAddr, insurerPremiumShare, true);
            }
        }
        
        // Distribute to reinsurers
        uint256 reinsurerCount = reinsurer.getReinsurerCount();
        console2.log("reinsurerCount:", reinsurerCount);
        
        for (uint256 i = 0; i < reinsurerCount; i++) {
            address reinsurerAddr = reinsurer.getReinsurerByIndex(i);
            console2.log("Processing reinsurer", i);
            console2.log("reinsurerAddr:", uint256(uint160(reinsurerAddr)));
            
            if (reinsurer.isRegisteredReinsurer(reinsurerAddr)) {
                uint256 reinsurerCollateral = reinsurer.getReinsurerCollateral(reinsurerAddr);
                console2.log("reinsurerCollateral:", reinsurerCollateral / 1e18);
                
                if (reinsurerCollateral > 0) {
                    // Calculate proportional share based on collateral
                    uint256 reinsurerPremiumShare = (reinsurerShare * reinsurerCollateral) / reinsuranceData.reinsuranceCapital;
                    
                    console2.log("reinsurerShare:", reinsurerShare / 1e18);
                    console2.log("reinsurerCollateral:", reinsurerCollateral / 1e18);
                    console2.log("reinsuranceData.reinsuranceCapital:", reinsuranceData.reinsuranceCapital / 1e18);
                    console2.log("reinsurerPremiumShare:", reinsurerPremiumShare / 1e18);
                    
                    // Credit reinsurer's internal balance
                    userBalances[reinsurerAddr] += reinsurerPremiumShare;
                    
                    // Update reinsurer's total premiums
                    reinsurer.addReinsurerPremiums(reinsurerAddr, reinsurerPremiumShare);
                    
                    emit PremiumDistributed(eventId, reinsurerAddr, reinsurerPremiumShare, false);
                } else {
                    console2.log("reinsurer has 0 collateral, skipping");
                }
            } else {
                console2.log("reinsurer is not registered, skipping");
            }
        }
        
        console2.log("=== END REINSURANCE DEBUG ===");
        
        // Clear accumulated premiums
        eventsLogic.clearAccumulatedPremiums(eventId);
        
        // Update reinsurance data with current system state
        updateReinsuranceData();
        
        // Emit the final event once
        emit EventPremiumsDistributed(eventId, totalPremiums, insurerShare, reinsurerShare);
    }
    
    /**
     * @dev Get the next available distribution time for an event
     * @param eventId The event ID
     * @param distributionInterval The distribution interval
     * @return The timestamp when distribution will be available
     */
    function getNextDistributionTime(uint256 eventId, uint256 distributionInterval) external view returns (uint256) {
        uint256 lastDistribution = eventLastDistributionTime[eventId];
        return lastDistribution + distributionInterval;
    }
    
    /**
     * @dev Check if distribution is available for an event
     * @param eventId The event ID
     * @param distributionInterval The distribution interval
     * @return True if distribution is available
     */
    function isDistributionAvailable(uint256 eventId, uint256 distributionInterval) external view returns (bool) {
        uint256 lastDistribution = eventLastDistributionTime[eventId];
        return block.timestamp >= lastDistribution + distributionInterval;
    }
    
    // Events for periodic distribution
    event PeriodicDistributionExecuted(
        uint256 indexed eventId,
        address indexed caller,
        uint256 premiumsDistributed,
        uint256 gratification,
        uint256 timestamp
    );
} 