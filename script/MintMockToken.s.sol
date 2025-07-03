// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MockToken.sol";

contract MintMockToken is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address to = 0x7019758Fc03CE9C0875a33cf620938c9468A4e0C; // Your MetaMask address
        address mockTokenAddr = 0x22753E4264FDDc6181dc7cce468904A80a363E44; // Updated MockToken address
        uint256 amount = 10000e18; // 10,000 tokens

        vm.startBroadcast(ownerPrivateKey);
        MockToken(mockTokenAddr).mint(to, amount);
        vm.stopBroadcast();
    }
} 