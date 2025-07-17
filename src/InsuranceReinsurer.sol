// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InsuranceStorage.sol";

contract InsuranceReinsurer is InsuranceStorage {
    event ReinsurerRegistered(address indexed reinsurer, uint256 collateral);
    event ReinsurerCapitalAdded(address indexed reinsurer, uint256 amount);

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @dev Register a reinsurer with virtual collateral (no actual ERC20 transfer)
     * @param reinsurerAddr Address of the reinsurer to register
     * @param collateral Amount of collateral (already transferred virtually in InsuranceCore)
     */
    function registerReinsurer(address reinsurerAddr, uint256 collateral) external {
        require(!reinsurers[reinsurerAddr].isActive, "Already registered");
        
        // No actual transfer needed - virtual transfer already done in InsuranceCore
        reinsurers[reinsurerAddr] = Reinsurer({
            collateral: collateral,
            consumedCapital: 0,
            totalPremiums: 0,
            isActive: true,
            lastPremiumClaim: 0,
            accumulatedPremiums: 0
        });
        reinsurerList.push(reinsurerAddr);
        emit ReinsurerRegistered(reinsurerAddr, collateral);
    }

    /**
     * @dev Add additional capital to an existing reinsurer (virtual transfer)
     * @param reinsurerAddr Address of the reinsurer to add capital to
     * @param amount Amount to add (will be handled by InsuranceCore)
     */
    function addReinsurerCapital(address reinsurerAddr, uint256 amount) external {
        require(reinsurers[reinsurerAddr].isActive, "Not registered");
        require(amount > 0, "Amount must be greater than 0");
        
        // Virtual transfer handled by InsuranceCore
        reinsurers[reinsurerAddr].collateral += amount;
        emit ReinsurerCapitalAdded(reinsurerAddr, amount);
    }

    // Placeholder functions for interface compatibility
    function claimReinsurerPremiums() external {
        // Implementation would go here
    }

    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256) {
        return reinsurers[reinsurerAddr].totalPremiums;
    }

    function getTotalReinsurerCapital() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < reinsurerList.length; i++) {
            address reinsurerAddr = reinsurerList[i];
            if (reinsurers[reinsurerAddr].isActive) {
                total += reinsurers[reinsurerAddr].collateral;
            }
        }
        return total;
    }

    function getReinsurerCount() external view returns (uint256) {
        return reinsurerList.length;
    }

    function getReinsurerByIndex(uint256 index) external view returns (address) {
        require(index < reinsurerList.length, "Index out of bounds");
        return reinsurerList[index];
    }

    function isRegisteredReinsurer(address reinsurerAddr) external view returns (bool isActive) {
        return reinsurers[reinsurerAddr].isActive;
    }

    function getReinsurerCollateral(address reinsurerAddr) external view returns (uint256) {
        return reinsurers[reinsurerAddr].collateral;
    }
}

interface IInsuranceReinsurer {
    function registerReinsurer(address reinsurerAddr, uint256 collateral) external;
    function addReinsurerCapital(address reinsurerAddr, uint256 amount) external;
    function claimReinsurerPremiums() external;
    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256);
    function getTotalReinsurerCapital() external view returns (uint256);
    function getReinsurerCount() external view returns (uint256);
    function getReinsurerByIndex(uint256 index) external view returns (address);
    function isRegisteredReinsurer(address reinsurerAddr) external view returns (bool isActive);
} 