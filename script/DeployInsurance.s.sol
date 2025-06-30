// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceOracle.sol";
import "../src/MockToken.sol";

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

        // Deploy insurance core
        InsuranceCore insurance = new InsuranceCore(address(mockToken));
        console.log("InsuranceCore deployed at:", address(insurance));

        // Register some events
        uint256 btcEvent = insurance.registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20, // 20% threshold
            500 // 5% base premium
        );
        console.log("BTC Crash event registered with ID:", btcEvent);

        uint256 aaveEvent = insurance.registerEvent(
            "AAVE Hack",
            "AAVE protocol gets hacked or exploited",
            100, // 100% threshold (any hack)
            1000 // 10% base premium
        );
        console.log("AAVE Hack event registered with ID:", aaveEvent);

        uint256 ethEvent = insurance.registerEvent(
            "ETH Crash",
            "Ethereum drops more than 30% in one day",
            30, // 30% threshold
            800 // 8% base premium
        );
        console.log("ETH Crash event registered with ID:", ethEvent);

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("MockToken:", address(mockToken));
        console.log("InsuranceOracle:", address(oracle));
        console.log("InsuranceCore:", address(insurance));
    }
} 