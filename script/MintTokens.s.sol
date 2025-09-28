// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/MockToken.sol";

contract MintTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // MockToken address from latest deployment
        MockToken mockToken = MockToken(0x5FbDB2315678afecb367f032d93F642f64180aa3);

        // Mint 10,000,000 tokens to default Anvil accounts
        // Account 0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        mockToken.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 10000000e18);
        
        // Account 1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
        mockToken.mint(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 10000000e18);
        
        // Account 2: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
        mockToken.mint(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, 10000000e18);

        vm.stopBroadcast();
        
        console.log("10,000,000 tokens minted successfully!");
        console.log("Account 0:", 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        console.log("Account 1:", 0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
        console.log("Account 2:", 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    }
}

