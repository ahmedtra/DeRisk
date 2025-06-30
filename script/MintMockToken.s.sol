// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MockToken.sol";

contract MintMockToken is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address to = 0x88D2A0F1Ce61Db8D0667f025fAe3438572466fFf;
        address mockTokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // update if needed
        uint256 amount = 10000e18; // 10,000 tokens

        vm.startBroadcast(ownerPrivateKey);
        MockToken(mockTokenAddr).mint(to, amount);
        vm.stopBroadcast();
    }
} 