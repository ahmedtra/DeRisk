// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsurancePolicyHolder.sol";

contract SetInsurer is Script {
    function run() external {
        uint256 privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        vm.startBroadcast(privateKey);

        // Get the deployed InsurancePolicyHolder contract
        InsurancePolicyHolder policyHolderContract = InsurancePolicyHolder(0xc5a5C42992dECbae36851359345FE25997F5C42d);

        console.log("=== Setting Insurer Address ===");
        
        // Set the insurer address to the deployer (the account with the private key)
        address insurerAddress = vm.addr(privateKey);
        console.log("Setting insurer address to:", insurerAddress);
        
        try policyHolderContract.setInsurer(insurerAddress) {
            console.log("SUCCESS: Insurer address set!");
            
            // Verify the insurer address was set
            address currentInsurer = policyHolderContract.insurer();
            console.log("Current insurer address:", currentInsurer);
        } catch Error(string memory reason) {
            console.log("ERROR: Set insurer failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: Set insurer failed with low level error");
            console.log("Low level data:", vm.toString(lowLevelData));
        }

        vm.stopBroadcast();
    }
}
