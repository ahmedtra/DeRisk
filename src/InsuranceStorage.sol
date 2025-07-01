// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract InsuranceStorage {
    using Counters for Counters.Counter;

    IERC20 public paymentToken;
    uint256 public constant LOCKUP_PERIOD = 7 days;
    uint256 public constant MIN_COLLATERAL = 1000 * 1e18;
    uint256 public constant TARGET_APY_INSURER = 1500;
    uint256 public constant TARGET_APY_REINSURER = 1000;
    uint256 public lastDistributionTime;
    uint256 public constant DISTRIBUTION_INTERVAL = 1 seconds;
    Counters.Counter internal _policyIds;

    struct Policy {
        address policyHolder;
        uint256 eventId;
        uint256 coverage;
        uint256 premium;
        uint256 startTime;
        uint256 activationTime;
        bool isActive;
        bool isClaimed;
    }

    struct Insurer {
        uint256 totalCollateral;
        uint256 availableCollateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
        uint256[] insuredPolicies;
        uint256[] allocatedEvents;
        mapping(uint256 => uint256) eventAllocations;
        uint256 lastPremiumClaim;
        uint256 accumulatedPremiums;
    }

    struct Reinsurer {
        uint256 collateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
        uint256 lastPremiumClaim;
        uint256 accumulatedPremiums;
    }

    mapping(uint256 => Policy) public policies;
    mapping(address => Insurer) public insurers;
    mapping(address => Reinsurer) public reinsurers;
    address[] public insurerList;
    address[] public reinsurerList;
} 