// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract BaseSecure is Ownable, Pausable, ReentrancyGuard {
    
    error ZeroAddress();
    error InvalidAmount();
    error NotAuthorized();

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _transferOwnership(initialOwner);
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
