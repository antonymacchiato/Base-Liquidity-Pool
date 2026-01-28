# base-liquidity-pool/contracts/LiquidityPool.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityPool is Ownable {
    struct PoolToken {
        IERC20 token;
        uint256 balance;
        uint256 weight;
    }
    
    struct LiquidityPosition {
        uint256 liquidityAmount;
        uint256[] tokenAmounts;
        uint256 lastUpdateTime;
    }
    
    PoolToken[] public poolTokens;
    mapping(address => LiquidityPosition) public liquidityPositions;
    mapping(address => uint256) public userShares;
    
    uint256 public totalSupply;
    uint256 public feeRate;
    
    event LiquidityAdded(
        address indexed user,
        uint256[] amounts,
        uint256 liquidityMinted
    );
    
    event LiquidityRemoved(
        address indexed user,
        uint256[] amounts,
        uint256 liquidityBurned
    );
    
    constructor(
        address[] memory tokens,
        uint256[] memory weights,
        uint256 _feeRate
    ) {
        require(tokens.length == weights.length, "Mismatched arrays");
        feeRate = _feeRate;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            poolTokens.push(PoolToken({
                token: IERC20(tokens[i]),
                balance: 0,
                weight: weights[i]
            }));
        }
    }
    
function addLiquidity(
        uint256[] calldata amounts
    ) external {
        require(amounts.length == poolTokens.length, "Invalid amounts array");
        
        uint256[] memory tokenAmounts = new uint256[](poolTokens.length);
        uint256 totalLiquidity = 0;
        
        for (uint256 i = 0; i < poolTokens.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(poolTokens[i].token.balanceOf(msg.sender) >= amounts[i], "Insufficient balance");
            
            poolTokens[i].token.transferFrom(msg.sender, address(this), amounts[i]);
            poolTokens[i].balance += amounts[i];
            
            tokenAmounts[i] = amounts[i];
            totalLiquidity += amounts[i];
        }
        
        uint256 sharesToMint = totalLiquidity;
        if (totalSupply > 0) {
            sharesToMint = (totalLiquidity * totalSupply) / getTotalValue();
        }
        
        userShares[msg.sender] += sharesToMint;
        totalSupply += sharesToMint;
        
        liquidityPositions[msg.sender] = LiquidityPosition({
            liquidityAmount: totalLiquidity,
            tokenAmounts: tokenAmounts,
            lastUpdateTime: block.timestamp
        });
        
        emit LiquidityAdded(msg.sender, amounts, sharesToMint);
    }
    
    function removeLiquidity(
        uint256 sharesToRemove
    ) external {
        require(userShares[msg.sender] >= sharesToRemove, "Insufficient shares");
        
        LiquidityPosition storage position = liquidityPositions[msg.sender];
        uint256[] memory amounts = new uint256[](poolTokens.length);
        uint256 totalValue = getTotalValue();
        
        for (uint256 i = 0; i < poolTokens.length; i++) {
            amounts[i] = (position.tokenAmounts[i] * sharesToRemove) / totalSupply;
            poolTokens[i].balance -= amounts[i];
            poolTokens[i].token.transfer(msg.sender, amounts[i]);
        }
        
        userShares[msg.sender] -= sharesToRemove;
        totalSupply -= sharesToRemove;
        
        emit LiquidityRemoved(msg.sender, amounts, sharesToRemove);
    }
    
    function getTotalValue() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            total += poolTokens[i].balance;
        }
        return total;
    } 
 } 



