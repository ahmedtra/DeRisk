// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceOracle.sol";
import "../src/MockToken.sol";
import "../src/InsurancePolicyHolder.sol";
import "../src/InsuranceInsurer.sol";
import "../src/InsuranceReinsurer.sol";
import "../src/InsuranceEvents.sol";

/**
 * @title InsuranceTest
 * @dev Comprehensive tests for the insurance system
 */
contract InsuranceTest is Test {
    
    InsuranceCore public insurance;
    InsuranceOracle public oracle;
    MockToken public mockToken;
    InsurancePolicyHolder public policyHolder;
    InsuranceInsurer public insurer;
    InsuranceReinsurer public reinsurer;
    InsuranceEvents public eventsLogic;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public eve = address(0x5);
    
    uint256 public btcEventId;
    uint256 public aaveEventId;
    uint256 public ethEventId;

    function setUp() public {
        // Deploy contracts
        mockToken = new MockToken();
        oracle = new InsuranceOracle();
        policyHolder = new InsurancePolicyHolder(address(mockToken));
        insurer = new InsuranceInsurer(address(mockToken));
        reinsurer = new InsuranceReinsurer(address(mockToken));
        eventsLogic = new InsuranceEvents();
        insurance = new InsuranceCore(address(policyHolder), address(insurer), address(reinsurer), address(eventsLogic));
        // Mint tokens to test accounts
        mockToken.mint(alice, 100000e18);
        mockToken.mint(bob, 100000e18);
        mockToken.mint(charlie, 100000e18);
        mockToken.mint(david, 100000e18);
        mockToken.mint(eve, 100000e18);
        
        // Register events
        insurance.registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20,
            500
        );
        btcEventId = 1;
        
        insurance.registerEvent(
            "AAVE Hack",
            "AAVE protocol gets hacked or exploited",
            100,
            1000
        );
        aaveEventId = 2;
        
        insurance.registerEvent(
            "ETH Crash",
            "Ethereum drops more than 30% in one day",
            30,
            800
        );
        ethEventId = 3;
        // Transfer ownership to alice at the end
        insurance.transferOwnership(alice);
        policyHolder.setEventsLogic(address(eventsLogic));
        policyHolder.setInsurer(address(insurer));
        insurer.setPolicyHolder(address(policyHolder));
        insurer.setEventsLogic(address(eventsLogic));
    }

    function testDeployment() public {
        assertEq(mockToken.balanceOf(alice), 100000e18);
    }


    function testRegisterInsurer() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        vm.stopPrank();
        (uint256 totalCollateral, , , , bool isActive) = insurer.insurers(alice);
        assertTrue(isActive);
        assertEq(totalCollateral, 10000e18);
    }

    function testRegisterReinsurer() public {
        vm.startPrank(bob);
        mockToken.approve(address(reinsurer), 20000e18);
        reinsurer.registerReinsurer(20000e18);
        vm.stopPrank();
        (uint256 collateral, , , bool isActive) = reinsurer.reinsurers(bob);
        assertTrue(isActive);
        assertEq(collateral, 20000e18);
    }

    function testBuyPolicy() public {
        // Register insurer and allocate capital first
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        // Fund insurer contract for payout
        mockToken.transfer(address(insurer), 10000e18);
        vm.stopPrank();
        // Buy policy
        vm.startPrank(bob);
        mockToken.approve(address(policyHolder), 1000e18);
        policyHolder.buyPolicy(btcEventId, 5000e18, 1000e18);
        vm.stopPrank();
        // Activate policy after lockup
        vm.startPrank(bob);
        vm.warp(604801);
        policyHolder.activatePolicy(1);
        vm.stopPrank();
        // Trigger event
        vm.startPrank(alice);
        insurance.triggerEvent(btcEventId);
        vm.stopPrank();
        // Claim policy via insurer
        vm.startPrank(bob);
        uint256 balanceBefore = mockToken.balanceOf(bob);
        insurer.claimPolicy(1);
        uint256 balanceAfter = mockToken.balanceOf(bob);
        (address policyHolder_, uint256 eventId_, uint256 coverage_, uint256 premium_, uint256 startTime_, uint256 activationTime_, bool isActive_, bool isClaimed_) = policyHolder.getPolicy(1);
        assertEq(policyHolder_, bob);
        assertEq(eventId_, btcEventId);
        assertEq(coverage_, 5000e18);
        assertEq(premium_, 1000e18);
        assertTrue(isActive_);
        assertTrue(isClaimed_);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function testActivatePolicy() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        emit log_string("Insurer registered and capital allocated");
        vm.stopPrank();
        // Buy policy
        vm.startPrank(bob);
        mockToken.approve(address(policyHolder), 1000e18);
        policyHolder.buyPolicy(btcEventId, 5000e18, 1000e18);
        emit log_string("Policy bought");
        (address holder, uint256 eventId, uint256 coverage, uint256 premium, , , bool isActive_, bool isClaimed) = policyHolder.getPolicy(1);
        emit log_address(holder);
        emit log_uint(eventId);
        emit log_uint(coverage);
        emit log_uint(premium);
        emit log_string(isActive_ ? "true" : "false");
        emit log_string(isClaimed ? "true" : "false");
        vm.stopPrank();
        // Try to activate before lockup period
        vm.startPrank(bob);
        vm.expectRevert("Lockup not expired");
        policyHolder.activatePolicy(1);
        emit log_string("Tried to activate before lockup");
        vm.stopPrank();
        // Fast forward time and activate
        vm.warp(block.timestamp + 8 days);
        vm.startPrank(bob);
        policyHolder.activatePolicy(1);
        emit log_string("Activated after lockup");
        (holder, eventId, coverage, premium, , , isActive_, isClaimed) = policyHolder.getPolicy(1);
        emit log_address(holder);
        emit log_uint(eventId);
        emit log_uint(coverage);
        emit log_uint(premium);
        emit log_string(isActive_ ? "true" : "false");
        emit log_string(isClaimed ? "true" : "false");
        vm.stopPrank();
        assertTrue(isActive_);
    }

    function testCalculatePremium() public {
        // Register insurer and allocate capital first
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        vm.stopPrank();
        uint256 premium = insurance.calculatePremium(btcEventId, 1000e18);
        assertGt(premium, 0);
        uint256 premium2 = insurance.calculatePremium(btcEventId, 2000e18);
        assertGt(premium2, premium);
    }

    function testTriggerEvent() public {
        // Register insurer and allocate capital
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        // Fund insurer contract for payout
        mockToken.transfer(address(insurer), 10000e18);
        vm.stopPrank();
        // Register reinsurer
        vm.startPrank(bob);
        mockToken.approve(address(reinsurer), 20000e18);
        reinsurer.registerReinsurer(20000e18);
        vm.stopPrank();
        // Buy and activate policy
        vm.startPrank(charlie);
        mockToken.approve(address(policyHolder), 1000e18);
        policyHolder.buyPolicy(btcEventId, 5000e18, 1000e18);
        vm.warp(604801);
        policyHolder.activatePolicy(1);
        uint256 balanceBefore = mockToken.balanceOf(charlie);
        vm.stopPrank();
        // Trigger event
        vm.startPrank(alice);
        insurance.triggerEvent(btcEventId);
        vm.stopPrank();
        // Claim policy via insurer
        vm.startPrank(charlie);
        insurer.claimPolicy(1);
        uint256 balanceAfter = mockToken.balanceOf(charlie);
        assertGt(balanceAfter, balanceBefore);
        vm.stopPrank();
    }

    function testMultiplePolicies() public {
        // Register insurer and allocate capital to two events
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 5000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 5000e18);
        insurer.allocateToEvent(aaveEventId, 5000e18);
        policyHolder.setEventInsurerCapital(aaveEventId, 5000e18);
        // Fund insurer contract for payout
        mockToken.transfer(address(insurer), 10000e18);
        vm.stopPrank();
        // Buy two policies
        vm.startPrank(charlie);
        mockToken.approve(address(policyHolder), 2000e18);
        policyHolder.buyPolicy(btcEventId, 5000e18, 1000e18);
        policyHolder.buyPolicy(aaveEventId, 3000e18, 1000e18);
        // Activate both policies after lockup
        vm.warp(604801);
        policyHolder.activatePolicy(1);
        policyHolder.activatePolicy(2);
        vm.stopPrank();
        // Trigger BTC event
        vm.startPrank(alice);
        insurance.triggerEvent(btcEventId);
        vm.stopPrank();
        // Claim BTC policy via insurer
        vm.startPrank(charlie);
        insurer.claimPolicy(1);
        (,,,,,,,bool btcClaimed) = policyHolder.getPolicy(1);
        (,,,,,,,bool aaveClaimed) = policyHolder.getPolicy(2);
        assertTrue(btcClaimed);
        assertFalse(aaveClaimed);
        vm.stopPrank();
    }

    function testOraclePriceUpdate() public {
        // Use the owner account (deployer) for oracle operations
        vm.startPrank(address(this));
        oracle.addOracle(alice, "Test Oracle");
        vm.stopPrank();
        
        vm.startPrank(alice);
        oracle.updatePrice("BTC", 50000e8, 95);
        vm.stopPrank();
        
        uint256 price = oracle.getPrice("BTC");
        assertEq(price, 50000e8);
    }

    function testOracleEventTrigger() public {
        // Use the owner account for triggering events
        vm.startPrank(address(this));
        oracle.triggerEvent(1, "BTC dropped 25% in one day");
        vm.stopPrank();
        
        InsuranceOracle.EventData memory eventData = oracle.getEventData(1);
        assertTrue(eventData.isTriggered);
        assertEq(eventData.triggerReason, "BTC dropped 25% in one day");
    }

    function test_RevertWhen_InsufficientCollateral() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 500e18);
        vm.expectRevert("Insufficient collateral");
        insurer.registerInsurer(500e18);
        vm.stopPrank();
    }

    function test_RevertWhen_DuplicateRegistration() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 20000e18);
        insurer.registerInsurer(10000e18);
        vm.expectRevert("Already registered");
        insurer.registerInsurer(10000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyPolicyWithoutInsurer() public {
        // No insurers registered
        vm.startPrank(alice);
        mockToken.approve(address(policyHolder), 1000e18);
        vm.expectRevert();
        policyHolder.buyPolicy(btcEventId, 5000e18, 1000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_TriggerNonExistentEvent() public {
        vm.expectRevert();
        insurance.triggerEvent(999);
    }

    function test_RevertWhen_OracleUnauthorized() public {
        vm.startPrank(alice);
        vm.expectRevert("Not authorized oracle");
        oracle.updatePrice("BTC", 50000e8, 95);
        vm.stopPrank();
    }

    function testPauseUnpauseOracle() public {
        // Use the owner account for pause/unpause operations
        vm.startPrank(address(this));
        oracle.pause();
        assertTrue(oracle.paused());
        
        oracle.unpause();
        assertFalse(oracle.paused());
        vm.stopPrank();
    }

    // ===== ADD INSURER CAPITAL TESTS =====

    function testAddInsurerCapital() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        mockToken.approve(address(insurer), 5000e18);
        insurer.addInsurerCapital(5000e18);
        insurer.allocateToEvent(btcEventId, 5000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 5000e18);
        vm.stopPrank();
        (uint256 totalCollateral, , , , bool isActive) = insurer.insurers(alice);
        assertTrue(isActive);
        assertEq(totalCollateral, 15000e18);
    }

    function testAddInsurerCapitalMultipleTimes() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        ( , , uint256 initialConsumedCapital, , ) = insurer.insurers(alice);
        // Add capital multiple times
        mockToken.approve(address(insurer), 5000e18);
        insurer.addInsurerCapital(5000e18);
        insurer.allocateToEvent(btcEventId, 5000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 5000e18);
        mockToken.approve(address(insurer), 3000e18);
        insurer.addInsurerCapital(3000e18);
        insurer.allocateToEvent(btcEventId, 3000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 3000e18);
        mockToken.approve(address(insurer), 2000e18);
        insurer.addInsurerCapital(2000e18);
        insurer.allocateToEvent(btcEventId, 2000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 2000e18);
        (uint256 finalCollateral, , uint256 finalConsumedCapital, , ) = insurer.insurers(alice);
        assertEq(finalCollateral, 20000e18);
        assertEq(finalConsumedCapital, initialConsumedCapital);
        vm.stopPrank();
    }

    function testAddInsurerCapitalWithLargeAmount() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        ( , , uint256 initialConsumedCapital, , ) = insurer.insurers(alice);
        uint256 largeAmount = 50000e18;
        mockToken.approve(address(insurer), largeAmount);
        insurer.addInsurerCapital(largeAmount);
        insurer.allocateToEvent(btcEventId, largeAmount);
        policyHolder.setEventInsurerCapital(btcEventId, largeAmount);
        (uint256 finalCollateral, , uint256 finalConsumedCapital, , ) = insurer.insurers(alice);
        assertEq(finalCollateral, 60000e18);
        assertEq(finalConsumedCapital, initialConsumedCapital);
        vm.stopPrank();
    }

    function testAddInsurerCapitalWithSmallAmount() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        ( , , uint256 initialConsumedCapital, , ) = insurer.insurers(alice);
        uint256 smallAmount = 1e18;
        mockToken.approve(address(insurer), smallAmount);
        insurer.addInsurerCapital(smallAmount);
        insurer.allocateToEvent(btcEventId, smallAmount);
        policyHolder.setEventInsurerCapital(btcEventId, smallAmount);
        (uint256 finalCollateral, , uint256 finalConsumedCapital, , ) = insurer.insurers(alice);
        assertEq(finalCollateral, 10001e18);
        assertEq(finalConsumedCapital, initialConsumedCapital);
        vm.stopPrank();
    }

    function testAddInsurerCapitalAfterPolicyCreation() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        ( , , uint256 initialConsumedCapital, , ) = insurer.insurers(alice);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        vm.stopPrank();
        vm.startPrank(bob);
        mockToken.approve(address(policyHolder), 1000e18);
        policyHolder.buyPolicy(btcEventId, 5000e18, 1000e18);
        vm.stopPrank();
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 5000e18);
        insurer.addInsurerCapital(5000e18);
        insurer.allocateToEvent(btcEventId, 5000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 5000e18);
        (uint256 finalCollateral, , uint256 finalConsumedCapital, , ) = insurer.insurers(alice);
        assertEq(finalCollateral, 15000e18);
        assertEq(finalConsumedCapital, initialConsumedCapital);
        vm.stopPrank();
    }

    function testAddInsurerCapitalTokenTransfer() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        uint256 balanceBefore = mockToken.balanceOf(alice);
        uint256 additionalAmount = 5000e18;
        mockToken.approve(address(insurer), additionalAmount);
        insurer.addInsurerCapital(additionalAmount);
        uint256 balanceAfter = mockToken.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore - additionalAmount);
        vm.stopPrank();
    }

    function testAddInsurerCapitalContractBalance() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurer), 10000e18);
        insurer.registerInsurer(10000e18);
        insurer.allocateToEvent(btcEventId, 10000e18);
        policyHolder.setEventInsurerCapital(btcEventId, 10000e18);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(insurer));
        uint256 additionalAmount = 5000e18;
        mockToken.approve(address(insurer), additionalAmount);
        insurer.addInsurerCapital(additionalAmount);
        uint256 contractBalanceAfter = mockToken.balanceOf(address(insurer));
        assertEq(contractBalanceAfter, contractBalanceBefore + additionalAmount);
        vm.stopPrank();
    }
} 