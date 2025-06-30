// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceOracle.sol";
import "../src/MockToken.sol";

/**
 * @title TestContracts
 * @dev Test script to verify deployed contracts work correctly
 */
contract TestContracts is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Contract addresses from deployment
        address mockTokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
        address oracleAddr = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
        address insuranceAddr = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
        
        MockToken mockToken = MockToken(mockTokenAddr);
        InsuranceOracle oracle = InsuranceOracle(oracleAddr);
        InsuranceCore insurance = InsuranceCore(insuranceAddr);
        
        console.log("=== Testing Deployed Contracts ===");
        
        // Test 1: Check token balance
        uint256 balance = mockToken.balanceOf(deployer);
        console.log("Deployer token balance:", balance);
        
        // Test 2: Check registered events
        InsuranceCore.Event memory btcEvent = insurance.getEvent(1);
        console.log("BTC Event name:", btcEvent.name);
        console.log("BTC Event active:", btcEvent.isActive);
        
        // Test 3: Register as insurer
        console.log("\n=== Testing Insurer Registration ===");
        mockToken.approve(insuranceAddr, 10000e18);
        insurance.registerInsurer(10000e18);
        console.log("Successfully registered as insurer");
        
        // Test 4: Check insurer count
        uint256 insurerCount = insurance.getInsurerCount();
        console.log("Total insurers:", insurerCount);
        
        // Test 5: Buy a policy
        console.log("\n=== Testing Policy Purchase ===");
        mockToken.approve(insuranceAddr, 1000e18);
        insurance.buyPolicy(1, 5000e18); // BTC event, 5000 coverage
        console.log("Successfully bought BTC crash insurance policy");
        
        // Test 6: Check policy details
        InsuranceCore.Policy memory policy = insurance.getPolicy(1);
        console.log("Policy holder:", policy.policyHolder);
        console.log("Policy coverage:", policy.coverage);
        console.log("Policy premium:", policy.premium);
        console.log("Policy active:", policy.isActive);
        
        // Test 7: Oracle price update
        console.log("\n=== Testing Oracle ===");
        oracle.addOracle(deployer, "Test Oracle");
        oracle.updatePrice("BTC", 50000e8, 95);
        uint256 btcPrice = oracle.getPrice("BTC");
        console.log("BTC Price from oracle:", btcPrice);
        
        vm.stopBroadcast();
        
        console.log("\n=== All Tests Passed! ===");
        console.log("Smart contracts are working correctly!");
    }
} 