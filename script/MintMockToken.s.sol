// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MockToken.sol";

contract MintMockToken is Script {
    function run() external {
        uint256 ownerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address to = 0x3B8c863181aC8c8c5B3428bC3068e3192fE9cd88; // Target address
        address mockTokenAddr = 0x9A676e781A523b5d0C0e43731313A708CB607508; // Deployed MockToken address
        uint256 amount = 10000e18; // 10,000 tokens

        vm.startBroadcast(ownerPrivateKey);
        MockToken(mockTokenAddr).mint(to, amount);
        vm.stopBroadcast();
    }
} 