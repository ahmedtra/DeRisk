// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceEvents.sol";
import "../src/InsurancePolicyHolder.sol";
import "../src/InsuranceInsurer.sol";
import "../src/InsuranceReinsurer.sol";
import "../src/InsuranceReinsuranceMath.sol";
import "../src/MockToken.sol";

contract SetupTestDataForDistribution is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get deployed contract addresses
        address mockToken = vm.envAddress("MOCK_TOKEN");
        address insuranceCore = vm.envAddress("INSURANCE_CORE");
        address insuranceEvents = vm.envAddress("INSURANCE_EVENTS");
        address insurancePolicyHolder = vm.envAddress("INSURANCE_POLICY_HOLDER");
        address insuranceInsurer = vm.envAddress("INSURANCE_INSURER");
        address insuranceReinsurer = vm.envAddress("INSURANCE_REINSURER");
        address insuranceReinsuranceMath = vm.envAddress("INSURANCE_REINSURANCE_MATH");

        // Get contract instances
        MockToken token = MockToken(mockToken);
        InsuranceCore core = InsuranceCore(insuranceCore);
        InsuranceEvents events = InsuranceEvents(insuranceEvents);
        InsurancePolicyHolder policyHolder = InsurancePolicyHolder(insurancePolicyHolder);
        InsuranceInsurer insurer = InsuranceInsurer(insuranceInsurer);
        InsuranceReinsurer reinsurer = InsuranceReinsurer(insuranceReinsurer);
        InsuranceReinsuranceMath reinsuranceMath = InsuranceReinsuranceMath(insuranceReinsuranceMath);

        // Test addresses (using Anvil's default accounts)
        address alice = vm.addr(1); // 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
        address bob = vm.addr(2);   // 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
        address charlie = vm.addr(3); // 0x90F79bf6EB2c4f870365E785982E1f101E93b906
        address david = vm.addr(4);   // 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

        console.log("Setting up test data for periodic distribution demonstration...");
        console.log("Alice (Insurer):", alice);
        console.log("Bob (Policy Holder):", bob);
        console.log("Charlie (Policy Holder):", charlie);
        console.log("David (Reinsurer):", david);

        // 1. Mint tokens to test accounts
        console.log("\n1. Minting tokens to test accounts...");
        token.mint(alice, 10000 * 1e18);      // 10,000 tokens for Alice
        token.mint(bob, 5000 * 1e18);         // 5,000 tokens for Bob
        token.mint(charlie, 3000 * 1e18);     // 3,000 tokens for Charlie
        token.mint(david, 8000 * 1e18);       // 8,000 tokens for David

        // 2. Register insurer (Alice)
        console.log("\n2. Registering Alice as insurer...");
        token.approve(insuranceCore, 10000 * 1e18);
        core.depositTokens(10000 * 1e18);
        core.registerInsurer(10000 * 1e18);

        // 3. Register reinsurer (David)
        console.log("\n3. Registering David as reinsurer...");
        vm.stopBroadcast();
        vm.startBroadcast(vm.addr(4)); // Switch to David's account
        token.approve(insuranceCore, 8000 * 1e18);
        core.depositTokens(8000 * 1e18);
        core.registerReinsurer(8000 * 1e18);

        // 4. Create insurance events
        console.log("\n4. Creating insurance events...");
        vm.stopBroadcast();
        vm.startBroadcast(deployerPrivateKey);
        
        // Event 1: BTC Crash
        uint256 btcEventId = events.registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20, // 20% threshold
            500 * 1e18 // 500 base premium
        );
        console.log("BTC Crash event created with ID:", btcEventId);

        // Event 2: AAVE Hack
        uint256 aaveEventId = events.registerEvent(
            "AAVE Hack",
            "AAVE protocol suffers a major security breach",
            15, // 15% threshold
            300 * 1e18 // 300 base premium
        );
        console.log("AAVE Hack event created with ID:", aaveEventId);

        // 5. Allocate insurer capital to events
        console.log("\n5. Allocating insurer capital to events...");
        vm.stopBroadcast();
        vm.startBroadcast(vm.addr(1)); // Switch to Alice's account
        
        insurer.allocateToEvent(alice, btcEventId, 6000 * 1e18);  // 6,000 to BTC event
        insurer.allocateToEvent(alice, aaveEventId, 4000 * 1e18); // 4,000 to AAVE event
        
        // Update event insurer capital
        policyHolder.setEventInsurerCapital(btcEventId, 6000 * 1e18);
        policyHolder.setEventInsurerCapital(aaveEventId, 4000 * 1e18);

        // 6. Buy policies
        console.log("\n6. Buying insurance policies...");
        
        // Bob buys BTC policy
        vm.stopBroadcast();
        vm.startBroadcast(vm.addr(2)); // Switch to Bob's account
        token.approve(insuranceCore, 5000 * 1e18);
        core.depositTokens(5000 * 1e18);
        core.buyPolicy(btcEventId, 3000 * 1e18, 1000 * 1e18); // 3,000 coverage, 1,000 max loss
        
        // Charlie buys AAVE policy
        vm.stopBroadcast();
        vm.startBroadcast(vm.addr(3)); // Switch to Charlie's account
        token.approve(insuranceCore, 3000 * 1e18);
        core.depositTokens(3000 * 1e18);
        core.buyPolicy(aaveEventId, 2000 * 1e18, 800 * 1e18); // 2,000 coverage, 800 max loss

        // 7. Fast forward time and activate policies
        console.log("\n7. Fast forwarding time and activating policies...");
        vm.warp(block.timestamp + 8 days); // 8 days later
        
        // Activate Bob's policy
        vm.stopBroadcast();
        vm.startBroadcast(vm.addr(2));
        policyHolder.activatePolicy(bob, 1);
        
        // Activate Charlie's policy
        vm.stopBroadcast();
        vm.startBroadcast(vm.addr(3));
        policyHolder.activatePolicy(charlie, 2);

        // 8. Collect ongoing premiums to accumulate for distribution
        console.log("\n8. Collecting ongoing premiums...");
        vm.stopBroadcast();
        vm.startBroadcast(deployerPrivateKey);
        
        // Collect premiums for BTC event
        core.collectOngoingPremiumsFromAllPolicyholders(btcEventId);
        
        // Collect premiums for AAVE event
        core.collectOngoingPremiumsFromAllPolicyholders(aaveEventId);

        // 9. Display final state
        console.log("\n9. Final state:");
        console.log("BTC Event accumulated premiums:", events.getEventAccumulatedPremiums(btcEventId));
        console.log("AAVE Event accumulated premiums:", events.getEventAccumulatedPremiums(aaveEventId));
        console.log("Alice (insurer) balance:", core.getUserBalance(alice));
        console.log("Bob (policy holder) balance:", core.getUserBalance(bob));
        console.log("Charlie (policy holder) balance:", core.getUserBalance(charlie));
        console.log("David (reinsurer) balance:", core.getUserBalance(david));

        console.log("\nTest data setup complete!");
        console.log("You can now test the periodic distribution functionality:");
        console.log("1. Navigate to the Periodic Distribution page in the frontend");
        console.log("2. Connect your wallet");
        console.log("3. Trigger distributions for the events");
        console.log("4. Check your balance for gratification rewards!");

        vm.stopBroadcast();
    }
}
