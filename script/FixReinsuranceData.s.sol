// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceReinsuranceMath.sol";

contract FixReinsuranceData is Script {
    
    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(deployerPrivateKey);

        // Fix reinsurance math contract
        InsuranceReinsuranceMath reinsuranceMath = InsuranceReinsuranceMath(0x547382C0D1b23f707918D3c83A77317B71Aa8470);
        
        // Set the insurance core address
        reinsuranceMath.setInsuranceCore(0x0a17FabeA4633ce714F1Fa4a2dcA62C3bAc4758d);
        console.log("Set insurance core address in reinsurance math");
        
        // Initialize reinsurance data with reasonable values
        // Total capital: 1000 ETH, Reinsurance capital: 500 ETH
        // Expected reinsurance loss: 100 ETH, Total expected loss: 200 ETH
        reinsuranceMath.updateReinsuranceData(
            1000000000000000000000, // 1000 ETH
            500000000000000000000,  // 500 ETH
            100000000000000000000,  // 100 ETH
            200000000000000000000   // 200 ETH
        );
        console.log("Updated reinsurance data");

        vm.stopBroadcast();
        console.log("Reinsurance data fixed successfully!");
    }
}

