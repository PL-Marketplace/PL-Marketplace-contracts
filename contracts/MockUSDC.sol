// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;
    
    constructor(address _owner) ERC20("Mock USDC", "USDC") Ownable(_owner) {}
    
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    // Faucet function for testing
    function faucet() public {
        _mint(msg.sender, 1000 * 10**DECIMALS); // 1000 USDC
    }
}
