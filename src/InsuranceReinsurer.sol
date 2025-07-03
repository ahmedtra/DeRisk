// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InsuranceReinsurer {
    IERC20 public paymentToken;
    struct Reinsurer {
        uint256 collateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
    }
    mapping(address => Reinsurer) public reinsurers;
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
            isActive: true
        });
        emit ReinsurerRegistered(reinsurerAddr, collateral);
    }

    /**
     * @dev Add additional capital to an existing reinsurer (virtual transfer)
     * @param amount Amount to add (will be handled by InsuranceCore)
     */
    function addReinsurerCapital(uint256 amount) external {
        require(reinsurers[msg.sender].isActive, "Not registered");
        require(amount > 0, "Amount must be greater than 0");
        
        // Virtual transfer handled by InsuranceCore
        reinsurers[msg.sender].collateral += amount;
        emit ReinsurerCapitalAdded(msg.sender, amount);
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
        // Would iterate through all reinsurers and sum collateral
        return total;
    }

    function getReinsurerCount() external view returns (uint256) {
        // Would return count of active reinsurers
        return 0;
    }

    function getReinsurerByIndex(uint256 index) external view returns (address) {
        // Would return reinsurer address by index
        return address(0);
    }
}

interface IInsuranceReinsurer {
    function registerReinsurer(address reinsurerAddr, uint256 collateral) external;
    function addReinsurerCapital(uint256 amount) external;
    function claimReinsurerPremiums() external;
    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256);
    function getTotalReinsurerCapital() external view returns (uint256);
    function getReinsurerCount() external view returns (uint256);
    function getReinsurerByIndex(uint256 index) external view returns (address);
} 