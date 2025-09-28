// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IInsuranceReinsurer {
    function registerReinsurer(address reinsurerAddr, uint256 collateral) external;
    function addReinsurerCapital(address reinsurerAddr, uint256 amount) external;
    function addReinsurerPremiums(address reinsurerAddr, uint256 amount) external;
    function claimReinsurerPremiums() external;
    function getReinsurerAccumulatedPremiums(address reinsurerAddr) external view returns (uint256);
    function getReinsurerConsumedCapital(address reinsurerAddr) external view returns (uint256);
    function getTotalReinsurerCapital() external view returns (uint256);
    function getReinsurerCount() external view returns (uint256);
    function getReinsurerByIndex(uint256 index) external view returns (address);
    function isRegisteredReinsurer(address reinsurerAddr) external view returns (bool isActive);
    function getReinsurerCollateral(address reinsurerAddr) external view returns (uint256);
    function setCore(address _core) external;
}

