// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceReinsuranceMath.sol";

contract DeployReinsuranceMath is Script {
    
    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(deployerPrivateKey);

        // Deploy a new reinsurance math contract
        InsuranceReinsuranceMath reinsuranceMath = new InsuranceReinsuranceMath();
        console.log("New InsuranceReinsuranceMath deployed at:", address(reinsuranceMath));
        
        // Set the insurance core address
        reinsuranceMath.setInsuranceCore(0x0a17FabeA4633ce714F1Fa4a2dcA62C3bAc4758d);
        console.log("Set insurance core address");
        
        // Initialize reinsurance data with reasonable values
        reinsuranceMath.updateReinsuranceData(
            1000000000000000000000, // 1000 ETH total capital
            500000000000000000000,  // 500 ETH reinsurance capital
            100000000000000000000,  // 100 ETH expected reinsurance loss
            200000000000000000000   // 200 ETH total expected loss
        );
        console.log("Updated reinsurance data");

        vm.stopBroadcast();
        console.log("Reinsurance math deployed and initialized successfully!");
        console.log("New address:", address(reinsuranceMath));
    }
}

