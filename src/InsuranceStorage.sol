// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InsuranceStorage {

    IERC20 public paymentToken;
    uint256 public constant LOCKUP_PERIOD = 7 days;
    uint256 public constant MIN_COLLATERAL = 1000 * 1e18;
    uint256 public constant REGISTRATION_FEE = 100 * 1e18; // 100 tokens registration fee
    uint256 public constant TARGET_APY_INSURER = 1500;
    uint256 public constant TARGET_APY_REINSURER = 1000;
    uint256 public lastDistributionTime;
    uint256 public constant DISTRIBUTION_INTERVAL = 1 seconds;
    uint256 internal _policyIds;

    // Virtual token management
    mapping(address => uint256) public userBalances;        // User's available balance
    mapping(address => uint256) public policyHolderFunds;   // Policy holder's funds (premiums paid)
    uint256 public totalSystemLiquidity;                   // Total tokens in the system
    uint256 public protocolFees;                           // Accumulated protocol fees from registrations

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

    mapping(uint256 => Policy) public policies;
} 