// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

/**
 * @title MockToken
 * @dev Mock ERC20 token for testing the insurance system
 */
contract MockToken is ERC20, Ownable {
    
    constructor() ERC20("Mock Insurance Token", "MIT") Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10**decimals()); // 1M tokens
    }

    /**
     * @dev Mint tokens for testing
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        console.log("transferFrom called by:", msg.sender);
        console.log("from:", from);
        console.log("to:", to);
        console.log("amount:", amount);
        console.log("allowance:", allowance(from, msg.sender));
        return super.transferFrom(from, to, amount);
    }
} 