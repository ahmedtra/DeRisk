// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsurancePolicyHolder.sol";

contract MarkPolicyClaimed is Script {
    function run() external {
        uint256 privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        vm.startBroadcast(privateKey);

        // Get the deployed InsurancePolicyHolder contract
        InsurancePolicyHolder policyHolderContract = InsurancePolicyHolder(0xc5a5C42992dECbae36851359345FE25997F5C42d);

        console.log("=== Marking Policy as Claimed ===");
        
        // Mark policy ID 1 as claimed
        uint256 policyId = 1;
        console.log("Attempting to mark policy ID:", policyId, "as claimed");
        
        try policyHolderContract.markPolicyClaimed(policyId) {
            console.log("SUCCESS: Policy marked as claimed!");
            
            // Get the updated policy data
            (address policyHolder, uint256 eventId, uint256 coverage, uint256 premium, uint256 startTime, uint256 activationTime, bool isActive, bool isClaimed) = policyHolderContract.getPolicy(policyId);
            
            console.log("Policy details after marking as claimed:");
            console.log("  Policy Holder:", policyHolder);
            console.log("  Event ID:", eventId);
            console.log("  Coverage:", coverage);
            console.log("  Premium:", premium);
            console.log("  Is Active:", isActive);
            console.log("  Is Claimed:", isClaimed);
        } catch Error(string memory reason) {
            console.log("ERROR: Mark policy claimed failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("ERROR: Mark policy claimed failed with low level error");
            console.log("Low level data:", vm.toString(lowLevelData));
        }

        vm.stopBroadcast();
    }
}
