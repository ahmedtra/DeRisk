// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MockToken.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceEvents.sol";
import "../src/InsurancePolicyHolder.sol";
import "../src/InsuranceInsurer.sol";
import "../src/InsuranceReinsurer.sol";

contract SetupTestData is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Get deployed contract addresses
        address mockToken = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
        address insuranceCore = 0x9FE46736679d2D9A65f0992F2272dE9c3c7f6Db0;
        address insuranceEvents = 0x09635F643e140090A9A8Dcd712eD6285858ceBef;
        address insurancePolicyHolder = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
        address insuranceInsurer = 0xdc64A140aA3C9818A2c9D11Dd7C16aEad0a2183a;
        address insuranceReinsurer = 0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E;
        
        // Create test accounts
        address alice = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address bob = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        address david = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
        
        console.log("Setting up test data...");
        
        // Mint tokens to test accounts
        MockToken(mockToken).mint(alice, 10000e18);
        MockToken(mockToken).mint(bob, 10000e18);
        MockToken(mockToken).mint(david, 10000e18);
        console.log("Minted tokens to test accounts");
        
        // Transfer tokens from deployer to test accounts (since minting doesn't give deployer tokens)
        // We need to mint to deployer first, then transfer
        MockToken(mockToken).mint(deployer, 30000e18);
        MockToken(mockToken).transfer(alice, 5000e18);
        MockToken(mockToken).transfer(david, 5000e18);
        MockToken(mockToken).transfer(bob, 1000e18);
        console.log("Transferred tokens to test accounts");
        
        vm.stopBroadcast();
        
        // Now impersonate accounts to deposit tokens to InsuranceCore
        // Impersonate Alice and deposit tokens
        vm.prank(alice);
        InsuranceCore(insuranceCore).depositTokens(5000e18);
        console.log("Alice deposited tokens");
        
        // Impersonate David and deposit tokens
        vm.prank(david);
        InsuranceCore(insuranceCore).depositTokens(5000e18);
        console.log("David deposited tokens");
        
        // Impersonate Bob and deposit tokens
        vm.prank(bob);
        InsuranceCore(insuranceCore).depositTokens(1000e18);
        console.log("Bob deposited tokens");
        
        // Now register as insurers and reinsurers
        vm.prank(alice);
        InsuranceCore(insuranceCore).registerInsurer(5000e18);
        console.log("Alice registered as insurer");
        
        vm.prank(david);
        InsuranceCore(insuranceCore).registerReinsurer(5000e18);
        console.log("David registered as reinsurer");
        
        // Create a test event
        vm.prank(deployer);
        InsuranceCore(insuranceCore).registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20, // 20% threshold
            500e18 // 500 tokens base premium
        );
        console.log("Created test event");
        
        // Buy a policy (Bob buys insurance)
        vm.prank(bob);
        InsuranceCore(insuranceCore).buyPolicy(
            1, // event ID
            500e18, // coverage amount
            1000e18 // max loss limit
        );
        console.log("Bob bought a policy");
        
        // Activate the policy
        vm.prank(bob);
        InsuranceCore(insuranceCore).activatePolicy(1);
        console.log("Policy activated");
        
        // Advance time by 2 weeks to allow premium collection
        vm.warp(block.timestamp + 2 weeks);
        console.log("Advanced time by 2 weeks");
        
        // Collect premiums from policyholders
        vm.prank(bob);
        InsuranceCore(insuranceCore).collectOngoingPremiumsFromAllPolicyholders(1);
        console.log("Collected ongoing premiums");
        
        console.log("Test data setup complete!");
        console.log("Alice (insurer):", alice);
        console.log("Bob (policyholder):", bob);
        console.log("David (reinsurer):", david);
        console.log("Event ID: 1");
        
        vm.stopBroadcast();
    }
}
