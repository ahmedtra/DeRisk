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

    function registerReinsurer(uint256 collateral) external {
        require(!reinsurers[msg.sender].isActive, "Already registered");
        paymentToken.transferFrom(msg.sender, address(this), collateral);
        reinsurers[msg.sender] = Reinsurer({
            collateral: collateral,
            consumedCapital: 0,
            totalPremiums: 0,
            isActive: true
        });
        emit ReinsurerRegistered(msg.sender, collateral);
    }

    function addReinsurerCapital(uint256 amount) external {
        require(reinsurers[msg.sender].isActive, "Not registered");
        paymentToken.transferFrom(msg.sender, address(this), amount);
        reinsurers[msg.sender].collateral += amount;
        emit ReinsurerCapitalAdded(msg.sender, amount);
    }
}

interface IInsuranceReinsurer {
    function registerReinsurer(uint256 collateral) external;
    function addReinsurerCapital(uint256 amount) external;
    function claimReinsurerPremiums() external;
    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256);
    function getTotalReinsurerCapital() external view returns (uint256);
    function getReinsurerCount() external view returns (uint256);
    function getReinsurerByIndex(uint256 index) external view returns (address);
} 