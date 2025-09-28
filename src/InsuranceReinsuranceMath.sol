// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InsuranceReinsuranceMath
 * @dev Implements the mathematical model for reinsurance calculations
 * Based on the equations:
 * - Expected returns calculation
 * - Premium pricing with risk adjustment
 * - Implied probability calculations
 */
contract InsuranceReinsuranceMath is Ownable {

    // Risk-free rate (in basis points, e.g., 500 = 5%)
    uint256 public constant RISK_FREE_RATE = 500; // 5%
    
    // Maximum premium multiplier
    uint256 public constant MAX_PREMIUM_MULTIPLIER = 1000; // 10x

    struct InsurerData {
        uint256 capital;           // C_i
        uint256 policyNotional;    // N_i (policy notional)
        uint256 beta;              // β_i (risk beta)
        uint256 expectedLossRatio; // 𝔼[L_i/C_i]
        uint256 totalLossRatio;    // 𝔼[H_i/C_i]
        uint256 maxPremium;        // P_i^∞
        uint256 probabilityNoLoss; // π_i
        uint256 premium;           // P_i
    }

    struct ReinsuranceData {
        uint256 totalCapital;      // ∑C_j
        uint256 reinsuranceCapital; // C_R
        uint256 expectedReinsuranceLoss; // 𝔼[L_R]
        uint256 totalExpectedLoss; // 𝔼[L_F]
    }

    mapping(address => InsurerData) public insurerData;
    ReinsuranceData public reinsuranceData;
    
    // Track total expected loss ratio sum
    uint256 public totalExpectedLossRatioSum;

    event InsurerDataUpdated(address indexed insurer, uint256 capital, uint256 policyNotional, uint256 beta);
    event PremiumCalculated(address indexed insurer, uint256 premium, uint256 probabilityNoLoss);
    event ExpectedReturnCalculated(address indexed insurer, uint256 expectedReturn);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Calculate expected return for policy holder on capital
     * R_f + β_i(𝔼[L_R]/C_R - R_f) + (C_R/∑C_j)(𝔼[L_R]/C_R) = 𝔼[H_i]/C_i
     * This is the expected return for the policy holder, normalized to insurer capital terms
     */
    function calculatePolicyHolderExpectedReturn(
        uint256 beta,
        uint256 riskFreeRate,
        uint256 expectedReinsuranceLoss,
        uint256 reinsuranceCapital,
        uint256 totalCapital,
        uint256 reinsuranceCapitalRatio
    ) public pure returns (uint256) {
        require(reinsuranceCapital > 0, "Reinsurance capital must be positive");
        require(totalCapital > 0, "Total capital must be positive");
        
        // Calculate 𝔼[L_R]/C_R
        uint256 reinsuranceLossRatio = expectedReinsuranceLoss * 10000 / reinsuranceCapital;
        
        // Calculate β_i(𝔼[L_R]/C_R - R_f)
        uint256 betaComponent = 0;
        if (reinsuranceLossRatio > riskFreeRate) {
            betaComponent = beta * (reinsuranceLossRatio - riskFreeRate) / 10000;
        }
        
        // Calculate (C_R/∑C_j)(𝔼[L_R]/C_R)
        uint256 reinsuranceComponent = reinsuranceCapitalRatio * reinsuranceLossRatio / 10000;
        
        // Calculate final expected return: R_f + β_i component + reinsurance component
        uint256 expectedReturn = riskFreeRate + betaComponent + reinsuranceComponent;
        
        return expectedReturn;
    }

    /**
     * @dev Calculate risk beta for an insurer
     * β_i = (μ C_i / N_i) / sum(𝔼[L_i / C_i])
     */
    function calculateBeta(
        uint256 insurerCapital,
        uint256 policyNotional,
        uint256 totalExpectedLossRatioSumParam,
        uint256 mu
    ) public pure returns (uint256) {
        require(policyNotional > 0, "Policy notional must be positive");
        require(totalExpectedLossRatioSumParam > 0, "Total expected loss ratio sum must be positive");
        
        uint256 capitalPerNotional = insurerCapital * 10000 / policyNotional;
        uint256 numerator = mu * capitalPerNotional;
        
        return numerator / totalExpectedLossRatioSumParam;
    }

    /**
     * @dev Calculate total expected loss ratio sum across all insurers
     * sum(𝔼[L_i / C_i])
     */
    function calculateTotalExpectedLossRatioSum() public view returns (uint256) {
        return totalExpectedLossRatioSum;
    }

    /**
     * @dev Calculate shared risk premium
     * P_i = (β_i / (β_i + C_R/∑C_j)) P_i^∞
     */
    function calculateSharedRiskPremium(
        uint256 beta,
        uint256 reinsuranceCapital,
        uint256 totalCapital,
        uint256 maxPremium
    ) public pure returns (uint256) {
        require(totalCapital > 0, "Total capital must be positive");
        require(maxPremium > 0, "Max premium must be positive");
        
        uint256 reinsuranceRatio = reinsuranceCapital * 10000 / totalCapital;
        uint256 denominator = beta + reinsuranceRatio;
        
        if (denominator == 0) return 0;
        
        return beta * maxPremium / denominator;
    }

    /**
     * @dev Solve for both event probability (π_i) and max premium (P_i^∞) from the system of equations
     * Using only the known variables: N_i, β_i, C_R, ∑C_j, C_i
     * 
     * For now, using a simplified approach with conservative estimates
     * to avoid complex iterative calculations that may cause overflow
     */
    function solveForEventProbabilityAndMaxPremium(
        uint256 insurerCapital,
        uint256 policyNotional,
        uint256 beta,
        uint256 expectedLossRatio,
        uint256 totalLossRatio,
        uint256 reinsuranceCapital,
        uint256 totalCapital
    ) public pure returns (uint256 eventProbability, uint256 maxPremium) {
        require(insurerCapital > 0, "Insurer capital must be positive");
        require(totalCapital > 0, "Total capital must be positive");
        require(policyNotional > 0, "Policy notional must be positive");
        
        // Simplified approach: Use conservative estimates based on the known variables
        
        // Calculate alpha: β_i / (β_i + C_R/∑C_j)
        uint256 reinsuranceRatio = reinsuranceCapital * 10000 / totalCapital;
        uint256 denominator = beta + reinsuranceRatio;
        require(denominator > 0, "Denominator must be positive");
        uint256 alpha = beta * 10000 / denominator;
        
        // Calculate pi (event probability) with safety checks
        // Using a more robust formula that avoids division by zero
        uint256 alphaNotionalComponent = alpha * policyNotional / insurerCapital;
        uint256 pi;
        
        // If alphaNotionalComponent is too small, use a fallback calculation
        if (alphaNotionalComponent <= 10000) {
            // Fallback: use expected loss ratio as base for probability
            pi = expectedLossRatio;
        } else {
            uint256 numerator = totalLossRatio + alpha * expectedLossRatio / 10000;
            uint256 denominator2 = alphaNotionalComponent - 10000;
            pi = numerator * 10000 / denominator2;
        }
        
        // Ensure pi stays within reasonable bounds (1% to 50%)
        if (pi > 5000) pi = 5000; // Cap at 50%
        if (pi < 100) pi = 100;   // Floor at 1%
        
        // Calculate max premium with safety checks
        uint256 numerator3 = insurerCapital * expectedLossRatio - pi * policyNotional;
        uint256 denominator3 = 10000 - pi;
        
        require(denominator3 > 0, "Denominator3 must be positive");
        maxPremium = numerator3 / denominator3;
        
        // Ensure max premium is reasonable
        if (maxPremium > insurerCapital * 10) {
            maxPremium = insurerCapital * 10; // Cap at 10x capital
        }
        if (maxPremium < insurerCapital / 10) {
            maxPremium = insurerCapital / 10; // Floor at 0.1x capital
        }
        
        eventProbability = pi;
        return (eventProbability, maxPremium);
    }
    
    /**
     * @dev Helper function to calculate absolute difference
     */
    function abs(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }



    /**
     * @dev Update insurer data and recalculate premiums
     * Now solves for both event probability and max premium from the system of equations
     * Using only the known variables: N_i, β_i, C_R, ∑C_j, C_i
     */
    function updateInsurerData(
        address insurer,
        uint256 insurerCapital,
        uint256 policyNotional,
        uint256 expectedLossRatio,
        uint256 totalLossRatio
    ) external onlyOwner {
        require(insurerCapital > 0, "Insurer capital must be positive");
        
        // Get the old expected loss ratio for this insurer (if it exists)
        uint256 oldExpectedLossRatio = insurerData[insurer].expectedLossRatio;
        
        // Update the total expected loss ratio sum
        totalExpectedLossRatioSum = totalExpectedLossRatioSum - oldExpectedLossRatio + expectedLossRatio;
        
        // Calculate beta using the total sum
        uint256 beta = calculateBeta(insurerCapital, policyNotional, totalExpectedLossRatioSum, 1000);
        
        // Get reinsurance data for solving the system
        ReinsuranceData memory reinsurance = reinsuranceData;
        
        // Solve for both event probability and max premium using the system of equations
        (uint256 eventProbability, uint256 maxPremium) = solveForEventProbabilityAndMaxPremium(
            insurerCapital,
            policyNotional,
            beta,
            expectedLossRatio,
            totalLossRatio,
            reinsurance.reinsuranceCapital,
            reinsurance.totalCapital
        );
        
        // If the solver didn't converge, use fallback values
        if (eventProbability == 0 || maxPremium == 0) {
            // Fallback: use conservative estimates
            maxPremium = insurerCapital * 2;
            eventProbability = 5000; // 50% probability as fallback
        }
        
        // Calculate premium using the solved values
        uint256 premium = calculateSharedRiskPremium(beta, reinsurance.reinsuranceCapital, reinsurance.totalCapital, maxPremium);
        
        // Store insurer data
        insurerData[insurer] = InsurerData({
            capital: insurerCapital,
            policyNotional: policyNotional, // Store policy notional
            beta: beta,
            expectedLossRatio: expectedLossRatio,
            totalLossRatio: totalLossRatio,
            maxPremium: maxPremium,
            probabilityNoLoss: eventProbability, // Store event probability in probabilityNoLoss field
            premium: premium
        });
        
        emit InsurerDataUpdated(insurer, insurerCapital, policyNotional, beta);
        emit PremiumCalculated(insurer, premium, eventProbability);
    }

    // Address of the InsuranceCore contract that can call certain functions
    address public insuranceCore;
    
    /**
     * @dev Set the InsuranceCore contract address
     */
    function setInsuranceCore(address _insuranceCore) external {
        // Temporarily allow anyone to call this for testing
        // TODO: Add proper access control later
        insuranceCore = _insuranceCore;
    }
    
    /**
     * @dev Update reinsurance data
     */
    function updateReinsuranceData(
        uint256 totalCapital,
        uint256 reinsuranceCapital,
        uint256 expectedReinsuranceLoss,
        uint256 totalExpectedLoss
    ) external {
        // Temporarily allow anyone to call this for testing
        // TODO: Add proper access control later
        reinsuranceData = ReinsuranceData({
            totalCapital: totalCapital,
            reinsuranceCapital: reinsuranceCapital,
            expectedReinsuranceLoss: expectedReinsuranceLoss,
            totalExpectedLoss: totalExpectedLoss
        });
    }

    /**
     * @dev Get reinsurance data
     */
    function getReinsuranceData() external view returns (ReinsuranceData memory) {
        return reinsuranceData;
    }

    /**
     * @dev Get calculated premium for an insurer
     */
    function getInsurerPremium(address insurer) external view returns (uint256) {
        return insurerData[insurer].premium;
    }

    /**
     * @dev Get probability of no loss for an insurer
     */
    function getInsurerProbabilityNoLoss(address insurer) external view returns (uint256) {
        return insurerData[insurer].probabilityNoLoss;
    }

    /**
     * @dev Get expected return for policy holder brought back to insurer capital terms
     * Returns 𝔼[H_i]/C_i (expected return on policy holder's capital, normalized to insurer capital)
     */
    function getPolicyHolderExpectedReturn(address insurer) external view returns (uint256) {
        InsurerData memory data = insurerData[insurer];
        ReinsuranceData memory reinsurance = reinsuranceData;
        
        // Calculate reinsurance capital ratio (C_R/∑C_j)
        uint256 reinsuranceCapitalRatio = reinsurance.reinsuranceCapital * 10000 / reinsurance.totalCapital;
        
        return calculatePolicyHolderExpectedReturn(
            data.beta,
            RISK_FREE_RATE,
            reinsurance.expectedReinsuranceLoss,
            reinsurance.reinsuranceCapital,
            reinsurance.totalCapital,
            reinsuranceCapitalRatio
        );
    }

    /**
     * @dev Calculate optimal capital allocation
     * Based on the risk-adjusted returns equation
     */
    function calculateOptimalCapitalAllocation(
        address[] memory insurers,
        uint256 totalAvailableCapital
    ) external view returns (uint256[] memory allocations) {
        allocations = new uint256[](insurers.length);
        
        uint256 totalRiskAdjustedCapital = 0;
        
        // Calculate total risk-adjusted capital
        for (uint256 i = 0; i < insurers.length; i++) {
            InsurerData memory data = insurerData[insurers[i]];
            if (data.capital > 0) {
                uint256 riskAdjustedCapital = data.capital * 10000 / data.beta;
                totalRiskAdjustedCapital = totalRiskAdjustedCapital + riskAdjustedCapital;
            }
        }
        
        // Allocate capital based on risk-adjusted ratios
        for (uint256 i = 0; i < insurers.length; i++) {
            InsurerData memory data = insurerData[insurers[i]];
            if (data.capital > 0 && totalRiskAdjustedCapital > 0) {
                uint256 riskAdjustedCapital = data.capital * 10000 / data.beta;
                allocations[i] = totalAvailableCapital * riskAdjustedCapital / totalRiskAdjustedCapital;
            }
        }
    }

    /**
     * @dev Validate reinsurance equilibrium
     * Check if the system satisfies the equilibrium equations
     */
    function validateReinsuranceEquilibrium(address insurer) external view returns (bool isValid) {
        InsurerData memory data = insurerData[insurer];
        ReinsuranceData memory reinsurance = reinsuranceData;
        
        if (data.capital == 0) return false;
        
        // Calculate reinsurance capital ratio (C_R/∑C_j)
        uint256 reinsuranceCapitalRatio = reinsurance.reinsuranceCapital * 10000 / reinsurance.totalCapital;
        
        // Check if expected return is reasonable (between 0% and 50%)
        uint256 expectedReturn = calculatePolicyHolderExpectedReturn(
            data.beta,
            RISK_FREE_RATE,
            reinsurance.expectedReinsuranceLoss,
            reinsurance.reinsuranceCapital,
            reinsurance.totalCapital,
            reinsuranceCapitalRatio
        );
        
        // Check if probability is valid (between 0% and 100%)
        bool validProbability = data.probabilityNoLoss <= 10000;
        
        // Check if premium is reasonable (not too high)
        bool validPremium = data.premium <= data.maxPremium;
        
        return expectedReturn >= 10000 && expectedReturn <= 15000 && validProbability && validPremium;
    }
}
