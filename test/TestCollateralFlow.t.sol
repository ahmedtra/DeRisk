// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {InsuranceCore} from "../src/InsuranceCore.sol";
import {InsuranceEvents} from "../src/InsuranceEvents.sol";
import {InsuranceInsurer} from "../src/InsuranceInsurer.sol";
import {InsuranceReinsurer} from "../src/InsuranceReinsurer.sol";
import {InsurancePolicyHolder} from "../src/InsurancePolicyHolder.sol";
import {InsuranceReinsuranceMath} from "../src/InsuranceReinsuranceMath.sol";
import {InsuranceOracle} from "../src/InsuranceOracle.sol";
import {InsuranceStorage} from "../src/InsuranceStorage.sol";
import {MockToken} from "../src/MockToken.sol";

contract TestCollateralFlow is Test {
    InsuranceCore public insurance;
    InsuranceEvents public events;
    InsuranceInsurer public insurer;
    InsuranceReinsurer public reinsurer;
    InsurancePolicyHolder public policyHolder;
    InsuranceReinsuranceMath public reinsuranceMath;
    InsuranceOracle public oracle;
    MockToken public mockToken;

    address public alice = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address public bob = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    address public charlie = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);

    uint256 public constant INITIAL_BALANCE = 200000e18; // 200,000 tokens
    uint256 public constant REGISTRATION_COLLATERAL = 10000e18; // 10,000 tokens
    uint256 public constant ADDITIONAL_CAPITAL = 15000e18; // 15,000 tokens
    uint256 public constant POLICY_COVERAGE = 15000e18; // 15,000 tokens
    uint256 public constant POLICY_PREMIUM = 100e18; // 100 tokens

    function setUp() public {
        // Deploy MockToken
        mockToken = new MockToken();
        
        // Deploy contracts
        events = new InsuranceEvents();
        insurer = new InsuranceInsurer(address(mockToken), address(policyHolder));
        reinsurer = new InsuranceReinsurer(address(mockToken));
        policyHolder = new InsurancePolicyHolder(address(mockToken));
        reinsuranceMath = new InsuranceReinsuranceMath();
        oracle = new InsuranceOracle();
        
        // Deploy InsuranceCore
        insurance = new InsuranceCore(
            address(mockToken),
            address(policyHolder),
            address(insurer),
            address(reinsurer),
            address(events),
            address(reinsuranceMath)
        );

        // Set up contract relationships
        insurer.setCore(address(insurance));
        insurer.setPolicyHolder(address(policyHolder));
        insurer.setEventsLogic(address(events));
        reinsurer.setCore(address(insurance));
        policyHolder.setEventsLogic(address(events));

        // Mint tokens to Alice
        mockToken.mint(alice, INITIAL_BALANCE);
        
        // Start with Alice
        vm.startPrank(alice);
    }

    function testCompleteInsuranceLifecycle() public {
        console2.log("=== INSURANCE LIFECYCLE TEST ===");
        console2.log("Initial setup...");
        
        // Phase 1: Initial Setup
        console2.log("\n--- PHASE 1: INITIAL SETUP ---");
        logBalances("Alice - Initial");
        
        // Approve tokens for all operations
        mockToken.approve(address(insurance), INITIAL_BALANCE);
        
        // Add tokens to virtual balance for functions that use userBalances
        insurance.depositTokens(POLICY_PREMIUM);
        
        logBalances("Alice - After approval");
        
        // Phase 2: Register as Insurer
        console2.log("\n--- PHASE 2: REGISTER AS INSURER ---");
        insurance.registerInsurer(REGISTRATION_COLLATERAL);
        
        // Initialize reinsurance data to avoid premium calculation issues
        reinsuranceMath.updateReinsuranceData(
            REGISTRATION_COLLATERAL + ADDITIONAL_CAPITAL, // total capital
            REGISTRATION_COLLATERAL,                      // reinsurance capital (same as registration)
            1000e18,                                     // expected reinsurance loss
            2000e18                                      // total expected loss
        );
        
        logBalances("Alice - After insurer registration");
        
        // Phase 3: Add Additional Capital
        console2.log("\n--- PHASE 3: ADD ADDITIONAL CAPITAL ---");
        insurance.addInsurerCapital(ADDITIONAL_CAPITAL);
        logBalances("Alice - After adding capital");
        
        // Phase 4: Register as Reinsurer
        console2.log("\n--- PHASE 4: REGISTER AS REINSURER ---");
        insurance.registerReinsurer(REGISTRATION_COLLATERAL);
        logBalances("Alice - After reinsurer registration");
        
        // Phase 5: Create Event
        console2.log("\n--- PHASE 5: CREATE EVENT ---");
        events.registerEvent("Test Event", "Test Description", 18000e18, 100e18);
        uint256 eventId = 1;
        logBalances("Alice - After creating event");
        logEventPremiums(eventId, "After creating event");
        
        // Phase 6: Allocate Capital to Event
        console2.log("\n--- PHASE 6: ALLOCATE CAPITAL TO EVENT ---");
        insurer.allocateToEvent(alice, eventId, ADDITIONAL_CAPITAL);
        logBalances("Alice - After allocating to event");
        logEventPremiums(eventId, "After allocating to event");
        
        // Phase 7: Buy Policy
        console2.log("\n--- PHASE 7: BUY POLICY ---");
        insurance.buyPolicy(eventId, POLICY_COVERAGE, POLICY_PREMIUM);
        logBalances("Alice - After buying policy");
        logEventPremiums(eventId, "After buying policy");
        
        // Phase 8: Advance Time
        console2.log("\n--- PHASE 8: ADVANCE TIME ---");
        vm.warp(block.timestamp + 10 days);
        logBalances("Alice - After advancing time");
        logEventPremiums(eventId, "After advancing time");
        
        // Phase 9: Activate Policy
        console2.log("\n--- PHASE 9: ACTIVATE POLICY ---");
        insurance.activatePolicy(1); // policyId = 1
        logBalances("Alice - After activating policy");
        logEventPremiums(eventId, "After activating policy");
        
        // Phase 10: Advance Time Again
        console2.log("\n--- PHASE 10: ADVANCE TIME AGAIN ---");
        vm.warp(block.timestamp + 10 days);
        logBalances("Alice - After second time advance");
        logEventPremiums(eventId, "After second time advance");
        
        // Phase 11: Collect Premiums
        console2.log("\n--- PHASE 11: COLLECT PREMIUMS ---");
        console2.log("Before collection - Event accumulated premiums:", events.getEventAccumulatedPremiums(eventId) / 1e18, "ETH");
        insurance.collectOngoingPremiumsFromAllPolicyholders(eventId);
        console2.log("After collection - Event accumulated premiums:", events.getEventAccumulatedPremiums(eventId) / 1e18, "ETH");
        logBalances("Alice - After collecting premiums");
        logEventPremiums(eventId, "After collecting premiums");
        
        // Phase 12: Distribute Premiums
        console2.log("\n--- PHASE 12: DISTRIBUTE PREMIUMS ---");
        console2.log("Before distribution - Event accumulated premiums:", events.getEventAccumulatedPremiums(eventId) / 1e18, "ETH");
        insurance.distributeAccumulatedPremiumsPeriodically(eventId, 1 days);
        console2.log("After distribution - Event accumulated premiums:", events.getEventAccumulatedPremiums(eventId) / 1e18, "ETH");
        logBalances("Alice - After distributing premiums");
        logEventPremiums(eventId, "After distributing premiums");
        
        // Phase 13: Final State
        console2.log("\n--- PHASE 13: FINAL STATE ---");
        logBalances("Alice - Final state");
        logEventPremiums(eventId, "Final state");
        
        // Summary
        console2.log("\n=== SUMMARY ===");
        (uint256 totalCollateral, uint256 consumedCapital, uint256 totalPremiums, ) = insurer.insurers(alice);
        console2.log("Total Collateral:", totalCollateral / 1e18, "ETH");
        console2.log("Consumed Capital:", consumedCapital / 1e18, "ETH");
        console2.log("Total Premiums:", totalPremiums / 1e18, "ETH");
        (uint256 reinsurerCollateral, , uint256 reinsurerTotalPremiums, , , ) = reinsurer.reinsurers(alice);
        console2.log("Reinsurer Total Collateral:", reinsurerCollateral / 1e18, "ETH");
        console2.log("Reinsurer Total Premiums:", reinsurerTotalPremiums / 1e18, "ETH");
        
        vm.stopPrank();
    }

    function logBalances(string memory phase) internal view {
        console2.log("\n", phase);
        console2.log("MockToken Balance:", mockToken.balanceOf(alice) / 1e18, "ETH");
        console2.log("InsuranceCore userBalance:", insurance.getUserBalance(alice) / 1e18, "ETH");
        console2.log("InsuranceCore lockedCollateral:", insurance.getUserLockedCollateral(alice) / 1e18, "ETH");
        console2.log("InsuranceCore insurer collateral:", insurer.getInsurerTotalCollateral(alice) / 1e18, "ETH");
        console2.log("InsuranceCore reinsurer collateral:", reinsurer.getReinsurerCollateral(alice) / 1e18, "ETH");
        
        // Get insurer data
        (uint256 totalCollateral, uint256 consumedCapital, uint256 totalPremiums, bool isActive) = insurer.insurers(alice);
        console2.log("InsuranceInsurer totalCollateral:", totalCollateral / 1e18, "ETH");
        console2.log("InsuranceInsurer consumedCapital:", consumedCapital / 1e18, "ETH");
        console2.log("InsuranceInsurer totalPremiums:", totalPremiums / 1e18, "ETH");
        console2.log("InsuranceInsurer isActive:", isActive);
        
        // Get reinsurer data
        (uint256 reinsurerCollateral, uint256 reinsurerConsumedCapital, uint256 reinsurerTotalPremiums, bool reinsurerIsActive, , ) = reinsurer.reinsurers(alice);
        console2.log("InsuranceReinsurer collateral:", reinsurerCollateral / 1e18, "ETH");
        console2.log("InsuranceReinsurer consumedCapital:", reinsurerConsumedCapital / 1e18, "ETH");
        console2.log("InsuranceReinsurer totalPremiums:", reinsurerTotalPremiums / 1e18, "ETH");
        console2.log("InsuranceReinsurer isActive:", reinsurerIsActive);
        
        console2.log("---");
    }

    function logEventPremiums(uint256 eventId, string memory phase) internal view {
        console2.log("\n", phase, "- Event Premiums:");
        console2.log("  Event accumulatedPremiums:", events.getEventAccumulatedPremiums(eventId) / 1e18, "ETH");
        console2.log("  Event totalPremiums:", events.getEventTotalCoverage(eventId) / 1e18, "ETH");
        console2.log("  Event totalInsurerCapital:", events.getEventInsurerCapital(eventId) / 1e18, "ETH");
        console2.log("---");
    }
}
