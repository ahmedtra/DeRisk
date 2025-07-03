// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InsurancePolicyHolder.sol";
import "./InsuranceEvents.sol";

contract InsuranceInsurer {
    IERC20 public paymentToken;
    struct Insurer {
        uint256 totalCollateral;
        uint256 availableCollateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
    }
    mapping(address => Insurer) public insurers;
    event InsurerRegistered(address indexed insurer, uint256 collateral);
    event InsurerCapitalAdded(address indexed insurer, uint256 amount);
    event CapitalAllocated(address indexed insurer, uint256 eventId, uint256 amount);

    uint256 public constant MIN_COLLATERAL = 1000 ether;

    InsurancePolicyHolder public policyHolder;
    InsuranceEvents public eventsLogic;
    address public core;

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @dev Register an insurer with virtual collateral (no actual ERC20 transfer)
     * @param insurerAddr Address of the insurer to register
     * @param collateral Amount of collateral (already transferred virtually in InsuranceCore)
     */
    function registerInsurer(address insurerAddr, uint256 collateral) external {
        require(!insurers[insurerAddr].isActive, "Already registered");
        require(collateral >= MIN_COLLATERAL, "Insufficient collateral");
        
        // No actual transfer needed - virtual transfer already done in InsuranceCore
        insurers[insurerAddr] = Insurer({
            totalCollateral: collateral,
            availableCollateral: collateral,
            consumedCapital: 0,
            totalPremiums: 0,
            isActive: true
        });
        emit InsurerRegistered(insurerAddr, collateral);
    }

    /**
     * @dev Add additional capital to an existing insurer (virtual transfer)
     * @param insurerAddr Address of the insurer to add capital to
     * @param amount Amount to add (will be handled by InsuranceCore)
     */
    function addInsurerCapital(address insurerAddr, uint256 amount) external {
        require(insurers[insurerAddr].isActive, "Not registered");
        require(amount > 0, "Amount must be greater than 0");
        
        // Virtual transfer handled by InsuranceCore
        insurers[insurerAddr].totalCollateral += amount;
        insurers[insurerAddr].availableCollateral += amount;
        emit InsurerCapitalAdded(insurerAddr, amount);
    }

    function allocateToEvent(uint256 eventId, uint256 amount) external {
        require(insurers[msg.sender].isActive, "Not registered");
        require(insurers[msg.sender].availableCollateral >= amount, "Insufficient collateral");
        insurers[msg.sender].availableCollateral -= amount;
        // Allocation logic would go here (event mapping, etc.)
        emit CapitalAllocated(msg.sender, eventId, amount);
    }

    function setCore(address _core) external {
        core = _core;
    }

    function claimPolicy(uint256 policyId) external {
        // Get policy info
        (address holder, uint256 eventId, uint256 coverage, , , , bool isActive, bool isClaimed) = policyHolder.getPolicy(policyId);
        require(holder == msg.sender, "Not policy holder");
        require(isActive, "Policy not active");
        require(!isClaimed, "Already claimed");
        // Check event is triggered
        (,,,bool isTriggered,,,,,,,,) = eventsLogic.getEvent(eventId);
        require(isTriggered, "Event not triggered");
        // Payout is now handled by InsuranceCore
        require(core != address(0), "Core not set");
        (bool ok, ) = core.call(abi.encodeWithSignature("processClaim(address,uint256,uint256)", holder, policyId, coverage));
        require(ok, "Claim payout failed");
        // Mark as claimed
        policyHolder.markPolicyClaimed(policyId);
    }

    function setPolicyHolder(address _policyHolder) external {
        policyHolder = InsurancePolicyHolder(_policyHolder);
    }

    function setEventsLogic(address _eventsLogic) external {
        eventsLogic = InsuranceEvents(_eventsLogic);
    }

    /**
     * @dev Check if an address is registered as an insurer
     * @param insurerAddr Address to check
     * @return isActive True if the address is an active insurer
     */
    function isRegisteredInsurer(address insurerAddr) external view returns (bool isActive) {
        return insurers[insurerAddr].isActive;
    }
}

interface IInsuranceInsurer {
    function registerInsurer(address insurerAddr, uint256 collateral) external;
    function addInsurerCapital(address insurerAddr, uint256 amount) external;
    function allocateToEvent(uint256 eventId, uint256 amount) external;
    function removeFromEvent(uint256 eventId, uint256 amount) external;
    function claimInsurerPremiums() external;
    function getInsurerEventAllocation(address insurerAddr, uint256 eventId) external view returns (uint256);
    function getInsurerAllocatedEvents(address insurerAddr) external view returns (uint256[] memory);
    function getEventInsurers(uint256 eventId) external view returns (address[] memory);
    function getEventTotalInsurerCapital(uint256 eventId) external view returns (uint256);
    function getInsurerAccumulatedPremiums(address insurerAddr) external view returns (uint256);
    function getInsurerCount() external view returns (uint256);
    function isRegisteredInsurer(address insurerAddr) external view returns (bool isActive);
} 