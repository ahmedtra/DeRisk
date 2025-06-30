// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/InsuranceCore.sol";
import "../src/InsuranceOracle.sol";
import "../src/MockToken.sol";

/**
 * @title InsuranceTest
 * @dev Comprehensive tests for the insurance system
 */
contract InsuranceTest is Test {
    
    InsuranceCore public insurance;
    InsuranceOracle public oracle;
    MockToken public mockToken;
    
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
        insurance = new InsuranceCore(address(mockToken));
        
        // Mint tokens to test accounts
        mockToken.mint(alice, 100000e18);
        mockToken.mint(bob, 100000e18);
        mockToken.mint(charlie, 100000e18);
        mockToken.mint(david, 100000e18);
        mockToken.mint(eve, 100000e18);
        
        // Register events
        btcEventId = insurance.registerEvent(
            "BTC Crash",
            "Bitcoin drops more than 20% in one day",
            20,
            500
        );
        
        aaveEventId = insurance.registerEvent(
            "AAVE Hack",
            "AAVE protocol gets hacked or exploited",
            100,
            1000
        );
        
        ethEventId = insurance.registerEvent(
            "ETH Crash",
            "Ethereum drops more than 30% in one day",
            30,
            800
        );
    }

    function testDeployment() public {
        assertEq(address(insurance.paymentToken()), address(mockToken));
        assertEq(mockToken.balanceOf(alice), 100000e18);
    }

    function testRegisterInsurer() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        (uint256 collateral, uint256 consumedCapital, uint256 totalPremiums, bool isActive) = insurance.insurers(alice);
        assertTrue(isActive);
        assertEq(collateral, 10000e18);
    }

    function testRegisterReinsurer() public {
        vm.startPrank(bob);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerReinsurer(20000e18);
        vm.stopPrank();
        
        (uint256 collateral, uint256 consumedCapital, uint256 totalPremiums, bool isActive) = insurance.reinsurers(bob);
        assertTrue(isActive);
        assertEq(collateral, 20000e18);
    }

    function testBuyPolicy() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        // Buy policy
        vm.startPrank(bob);
        mockToken.approve(address(insurance), 1000e18);
        insurance.buyPolicy(btcEventId, 5000e18);
        vm.stopPrank();
        
        InsuranceCore.Policy memory policy = insurance.getPolicy(1);
        assertEq(policy.policyHolder, bob);
        assertEq(policy.eventId, btcEventId);
        assertEq(policy.coverage, 5000e18);
        assertFalse(policy.isActive); // Should be inactive due to lockup
    }

    function testActivatePolicy() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        // Buy policy
        vm.startPrank(bob);
        mockToken.approve(address(insurance), 1000e18);
        insurance.buyPolicy(btcEventId, 5000e18);
        vm.stopPrank();
        
        // Try to activate before lockup period
        vm.startPrank(bob);
        vm.expectRevert("Lockup not expired");
        insurance.activatePolicy(1);
        vm.stopPrank();
        
        // Fast forward time and activate
        vm.warp(block.timestamp + 8 days);
        vm.startPrank(bob);
        insurance.activatePolicy(1);
        vm.stopPrank();
        
        InsuranceCore.Policy memory policy = insurance.getPolicy(1);
        assertTrue(policy.isActive);
    }

    function testCalculatePremium() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        uint256 premium = insurance.calculatePremium(btcEventId, 1000e18);
        assertGt(premium, 0);
        
        // Premium should increase with coverage
        uint256 premium2 = insurance.calculatePremium(btcEventId, 2000e18);
        assertGt(premium2, premium);
    }

    function testTriggerEvent() public {
        // Register insurer and reinsurer
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        vm.startPrank(bob);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerReinsurer(20000e18);
        vm.stopPrank();
        
        // Buy and activate policy
        vm.startPrank(charlie);
        mockToken.approve(address(insurance), 1000e18);
        insurance.buyPolicy(btcEventId, 5000e18);
        vm.warp(block.timestamp + 8 days);
        insurance.activatePolicy(1);
        vm.stopPrank();
        
        uint256 balanceBefore = mockToken.balanceOf(charlie);
        
        // Trigger event
        insurance.triggerEvent(btcEventId);
        
        uint256 balanceAfter = mockToken.balanceOf(charlie);
        assertGt(balanceAfter, balanceBefore); // Should receive payout
    }

    function testMultiplePolicies() public {
        // Register insurer and reinsurer
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        vm.startPrank(bob);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerReinsurer(20000e18);
        vm.stopPrank();
        
        // Buy multiple policies
        vm.startPrank(charlie);
        mockToken.approve(address(insurance), 2000e18);
        insurance.buyPolicy(btcEventId, 5000e18);
        insurance.buyPolicy(aaveEventId, 3000e18);
        vm.warp(block.timestamp + 8 days);
        insurance.activatePolicy(1);
        insurance.activatePolicy(2);
        vm.stopPrank();
        
        // Trigger one event
        insurance.triggerEvent(btcEventId);
        
        // Check that only BTC policy was claimed
        InsuranceCore.Policy memory btcPolicy = insurance.getPolicy(1);
        InsuranceCore.Policy memory aavePolicy = insurance.getPolicy(2);
        assertTrue(btcPolicy.isClaimed);
        assertFalse(aavePolicy.isClaimed);
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
        mockToken.approve(address(insurance), 500e18);
        vm.expectRevert("Insufficient collateral");
        insurance.registerInsurer(500e18);
        vm.stopPrank();
    }

    function test_RevertWhen_DuplicateRegistration() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerInsurer(10000e18);
        vm.expectRevert("Already registered");
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_BuyPolicyWithoutInsurer() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 1000e18);
        // This should revert because there are no insurers registered
        vm.expectRevert();
        insurance.buyPolicy(btcEventId, 5000e18);
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
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerInsurer(10000e18);
        
        // Check initial state
        (uint256 initialCollateral, , , bool isActive) = insurance.insurers(alice);
        assertTrue(isActive);
        assertEq(initialCollateral, 10000e18);
        
        // Add additional capital
        uint256 additionalAmount = 5000e18;
        insurance.addInsurerCapital(additionalAmount);
        
        // Check final state
        (uint256 finalCollateral, , , ) = insurance.insurers(alice);
        assertEq(finalCollateral, 15000e18); // 10000 + 5000
        vm.stopPrank();
    }

    function testAddInsurerCapitalMultipleTimes() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 50000e18);
        insurance.registerInsurer(10000e18);
        
        // Add capital multiple times
        insurance.addInsurerCapital(5000e18);
        insurance.addInsurerCapital(3000e18);
        insurance.addInsurerCapital(2000e18);
        
        // Check final state
        (uint256 finalCollateral, , , ) = insurance.insurers(alice);
        assertEq(finalCollateral, 20000e18); // 10000 + 5000 + 3000 + 2000
        vm.stopPrank();
    }

    function testAddInsurerCapitalWithLargeAmount() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 100000e18);
        insurance.registerInsurer(10000e18);
        
        // Add large amount of capital
        uint256 largeAmount = 50000e18;
        insurance.addInsurerCapital(largeAmount);
        
        // Check final state
        (uint256 finalCollateral, , , ) = insurance.insurers(alice);
        assertEq(finalCollateral, 60000e18); // 10000 + 50000
        vm.stopPrank();
    }

    function testAddInsurerCapitalWithSmallAmount() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 11000e18);
        insurance.registerInsurer(10000e18);
        
        // Add small amount of capital
        uint256 smallAmount = 1e18; // 1 token
        insurance.addInsurerCapital(smallAmount);
        
        // Check final state
        (uint256 finalCollateral, , , ) = insurance.insurers(alice);
        assertEq(finalCollateral, 10001e18); // 10000 + 1
        vm.stopPrank();
    }

    function test_RevertWhen_AddInsurerCapitalNotRegistered() public {
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        
        // Try to add capital without being registered
        vm.expectRevert("Not registered as insurer");
        insurance.addInsurerCapital(5000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_AddInsurerCapitalZeroAmount() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        
        // Try to add zero amount
        vm.expectRevert("Amount must be greater than 0");
        insurance.addInsurerCapital(0);
        vm.stopPrank();
    }

    function test_RevertWhen_AddInsurerCapitalInsufficientAllowance() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.registerInsurer(10000e18);
        
        // Try to add capital without sufficient allowance
        vm.expectRevert(); // Should revert due to insufficient allowance
        insurance.addInsurerCapital(5000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_AddInsurerCapitalInsufficientBalance() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 100000e18);
        insurance.registerInsurer(10000e18);
        
        // Try to add more capital than balance (alice has 100000e18, already used 10000e18)
        vm.expectRevert(); // Should revert due to insufficient balance
        insurance.addInsurerCapital(100000e18); // This would require 110000e18 total
        vm.stopPrank();
    }

    function testAddInsurerCapitalAfterPolicyCreation() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerInsurer(10000e18);
        vm.stopPrank();
        
        // Buy a policy (this will consume some capital)
        vm.startPrank(bob);
        mockToken.approve(address(insurance), 1000e18);
        insurance.buyPolicy(btcEventId, 5000e18);
        vm.stopPrank();
        
        // Add more capital after policy creation
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 10000e18);
        insurance.addInsurerCapital(5000e18);
        
        // Check final state
        (uint256 finalCollateral, , , ) = insurance.insurers(alice);
        assertEq(finalCollateral, 15000e18); // 10000 + 5000
        vm.stopPrank();
    }

    function testAddInsurerCapitalTokenTransfer() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerInsurer(10000e18);
        
        uint256 balanceBefore = mockToken.balanceOf(alice);
        uint256 additionalAmount = 5000e18;
        
        // Add capital
        insurance.addInsurerCapital(additionalAmount);
        
        uint256 balanceAfter = mockToken.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore - additionalAmount);
        
        vm.stopPrank();
    }

    function testAddInsurerCapitalContractBalance() public {
        // Register insurer first
        vm.startPrank(alice);
        mockToken.approve(address(insurance), 20000e18);
        insurance.registerInsurer(10000e18);
        
        uint256 contractBalanceBefore = mockToken.balanceOf(address(insurance));
        uint256 additionalAmount = 5000e18;
        
        // Add capital
        insurance.addInsurerCapital(additionalAmount);
        
        uint256 contractBalanceAfter = mockToken.balanceOf(address(insurance));
        assertEq(contractBalanceAfter, contractBalanceBefore + additionalAmount);
        
        vm.stopPrank();
    }
} 