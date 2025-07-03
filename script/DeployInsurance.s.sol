// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceOracle.sol";
import "../src/MockToken.sol";
import "../src/InsuranceInsurer.sol";
import "../src/InsuranceReinsurer.sol";
import "../src/InsurancePolicyHolder.sol";
import "../src/InsuranceEvents.sol";

/**
 * @title DeployInsurance
 * @dev Deployment script for the insurance system
 */
contract DeployInsurance is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock token
        MockToken mockToken = new MockToken();
        console.log("MockToken deployed at:", address(mockToken));

        // Deploy oracle
        InsuranceOracle oracle = new InsuranceOracle();
        console.log("InsuranceOracle deployed at:", address(oracle));

        // Deploy modular contracts
        InsurancePolicyHolder policyHolder = new InsurancePolicyHolder(address(mockToken));
        InsuranceInsurer insurer = new InsuranceInsurer(address(mockToken));
        InsuranceReinsurer reinsurer = new InsuranceReinsurer(address(mockToken));
        InsuranceEvents eventsLogic = new InsuranceEvents();
        
        // Deploy insurance core with payment token and modular addresses
        InsuranceCore insurance = new InsuranceCore(
            address(mockToken),  // payment token
            address(policyHolder), 
            address(insurer), 
            address(reinsurer), 
            address(eventsLogic)
        );
        console.log("InsuranceCore deployed at:", address(insurance));

        // Register some events
        insurance.registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20, // 20% threshold
            500 // 5% base premium
        );

        insurance.registerEvent(
            "AAVE Hack",
            "AAVE protocol gets hacked or exploited",
            100, // 100% threshold (any hack)
            1000 // 10% base premium
        );

        insurance.registerEvent(
            "ETH Crash",
            "Ethereum drops more than 30% in one day",
            30, // 30% threshold
            800 // 8% base premium
        );

        // After deploying contracts
        insurer.setCore(address(insurance));

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("MockToken:", address(mockToken));
        console.log("InsuranceOracle:", address(oracle));
        console.log("InsuranceCore:", address(insurance));
    }
} 