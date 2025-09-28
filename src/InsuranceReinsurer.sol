// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InsuranceReinsurer {
    IERC20 public paymentToken;
    address public core;
    
    struct Reinsurer {
        uint256 collateral;
        uint256 consumedCapital;
        uint256 totalPremiums;
        bool isActive;
        uint256 lastPremiumClaim;
        uint256 accumulatedPremiums;
    }
    
    mapping(address => Reinsurer) public reinsurers;
    address[] public reinsurerList;
    
    uint256 public constant TARGET_APY_REINSURER = 1000; // 10%
    
    event ReinsurerRegistered(address indexed reinsurer, uint256 collateral);
    event ReinsurerCapitalAdded(address indexed reinsurer, uint256 amount);

    constructor(address _paymentToken) {
        paymentToken = IERC20(_paymentToken);
    }

    /**
     * @dev Register a reinsurer with virtual collateral (no actual ERC20 transfer)
     * @param reinsurerAddr Address of the reinsurer to register
     * @param collateral Amount of collateral (already transferred virtually in InsuranceCore)
     */
    function registerReinsurer(address reinsurerAddr, uint256 collateral) external {
        require(!reinsurers[reinsurerAddr].isActive, "Already registered");
        
        // No actual transfer needed - virtual transfer already done in InsuranceCore
        reinsurers[reinsurerAddr] = Reinsurer({
            collateral: collateral,
            consumedCapital: 0,
            totalPremiums: 0,
            isActive: true,
            lastPremiumClaim: 0,
            accumulatedPremiums: 0
        });
        reinsurerList.push(reinsurerAddr);
        emit ReinsurerRegistered(reinsurerAddr, collateral);
    }

    /**
     * @dev Add additional capital to an existing reinsurer (virtual transfer)
     * @param reinsurerAddr Address of the reinsurer to add capital to
     * @param amount Amount to add (will be handled by InsuranceCore)
     */
    function addReinsurerCapital(address reinsurerAddr, uint256 amount) external {
        require(reinsurers[reinsurerAddr].isActive, "Not registered");
        require(amount > 0, "Amount must be greater than 0");
        
        // Virtual transfer handled by InsuranceCore
        reinsurers[reinsurerAddr].collateral += amount;
        emit ReinsurerCapitalAdded(reinsurerAddr, amount);
    }

    /**
     * @dev Add premiums to a reinsurer's accumulated premiums (called by InsuranceCore)
     * @param reinsurerAddr Address of the reinsurer to add premiums to
     * @param amount Amount of premiums to add
     */
    function addReinsurerPremiums(address reinsurerAddr, uint256 amount) external {
        require(msg.sender == core, "Only core can add premiums");
        require(reinsurers[reinsurerAddr].isActive, "Not registered");
        require(amount > 0, "Amount must be greater than 0");
        
        reinsurers[reinsurerAddr].totalPremiums += amount;
    }

    /**
     * @dev Set the core contract address
     * @param _core Address of the core contract
     */
    function setCore(address _core) external {
        core = _core;
    }

    // Placeholder functions for interface compatibility
    function claimReinsurerPremiums() external {
        // Implementation would go here
    }

    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256) {
        return reinsurers[reinsurerAddr].totalPremiums;
    }

    function getReinsurerConsumedCapital(address reinsurerAddr) external view returns (uint256) {
        // For reinsurers, consumedCapital represents their active reinsurance exposure
        // This is calculated based on their total premiums and target APY
        if (reinsurers[reinsurerAddr].totalPremiums == 0) {
            return 0;
        }
        
        // Calculate active exposure based on premiums earned and target APY
        // Formula: (Total Premiums * 365 days) / Target APY
        // This gives us the capital that would be needed to generate these premiums at the target rate
        uint256 annualizedPremiums = reinsurers[reinsurerAddr].totalPremiums * 365 days;
        uint256 targetAPY = TARGET_APY_REINSURER; // 1000 basis points = 10%
        
        if (targetAPY == 0) {
            return 0;
        }
        
        return annualizedPremiums / targetAPY;
    }

    /**
     * @dev Get total reinsurer capital across all registered reinsurers
     */
    function getTotalReinsurerCapital() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < reinsurerList.length; i++) {
            total += reinsurers[reinsurerList[i]].collateral;
        }
        return total;
    }

    /**
     * @dev Get reinsurer collateral for a specific address
     */
    function getReinsurerCollateral(address reinsurerAddr) external view returns (uint256) {
        return reinsurers[reinsurerAddr].collateral;
    }

    /**
     * @dev Check if an address is registered as a reinsurer
     */
    function isRegisteredReinsurer(address reinsurerAddr) external view returns (bool) {
        return reinsurers[reinsurerAddr].isActive;
    }

    /**
     * @dev Get reinsurer count
     */
    function getReinsurerCount() external view returns (uint256) {
        return reinsurerList.length;
    }

    /**
     * @dev Get reinsurer's deployed capital (capital allocated to events)
     * For reinsurers, this is currently 0 as they don't allocate to specific events
     * They provide general reinsurance coverage across all events
     */
    function getReinsurerDeployedCapital(address reinsurerAddr) external view returns (uint256) {
        // Reinsurers don't allocate capital to specific events like insurers do
        // They provide general reinsurance coverage across the entire system
        // So their deployed capital is always 0
        return 0;
    }



    function getReinsurerByIndex(uint256 index) external view returns (address) {
        require(index < reinsurerList.length, "Index out of bounds");
        return reinsurerList[index];
    }
}

// Interface moved to separate file 