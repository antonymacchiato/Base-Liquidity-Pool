// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LiquidityPoolV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    struct PoolToken {
        IERC20 token;
        uint256 balance;
        uint256 weight;
        uint256 price;
        uint256 lastUpdate;
    }

    struct LiquidityPosition {
        uint256 liquidityAmount;
        uint256[] tokenAmounts;
        uint256 lastUpdateTime;
        uint256[] weights;
        uint256 totalValue;
    }

    struct PoolConfig {
        uint256 feeRate;
        uint256 adminFee;
        uint256 minLiquidity;
        uint256 maxLiquidity;
        bool enabled;
        uint256 minWeight;
        uint256 maxWeight;
    }

    struct SwapFee {
        uint256 swapFee;
        uint256 adminSwapFee;
        uint256 protocolFee;
    }

    mapping(address => PoolToken) public poolTokens;
    mapping(address => LiquidityPosition) public liquidityPositions;
    mapping(address => uint256) public userShares;
    mapping(address => uint256) public userLiquidity;
    
    PoolToken[] public poolTokenList;
    PoolConfig public poolConfig;
    SwapFee public swapFee;
    
    uint256 public totalSupply;
    uint256 public constant MAX_WEIGHT = 10000;
    uint256 public constant MIN_WEIGHT = 100;
    uint256 public constant MAX_FEE_RATE = 10000; // 100%
    uint256 public constant MIN_FEE_RATE = 10; // 0.1%
    
   
    event LiquidityAdded(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 liquidityMinted,
        uint256 timestamp
    );
    
    event LiquidityRemoved(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 liquidityBurned,
        uint256 timestamp
    );
    
    event TokenSwapped(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        uint256 timestamp
    );
    
    event PoolConfigUpdated(
        uint256 feeRate,
        uint256 adminFee,
        uint256 minLiquidity,
        uint256 maxLiquidity
    );
    
    event FeeUpdated(
        uint256 swapFee,
        uint256 adminSwapFee,
        uint256 protocolFee
    );
    
    event TokenAdded(
        address indexed token,
        uint256 weight,
        uint256 timestamp
    );
    
    event TokenRemoved(
        address indexed token,
        uint256 timestamp
    );

    constructor(
        uint256 _feeRate,
        uint256 _adminFee,
        uint256 _minLiquidity,
        uint256 _maxLiquidity
    ) {
        require(_feeRate <= MAX_FEE_RATE, "Fee rate too high");
        require(_adminFee <= MAX_FEE_RATE, "Admin fee too high");
        require(_minLiquidity <= _maxLiquidity, "Invalid liquidity limits");
        
        poolConfig = PoolConfig({
            feeRate: _feeRate,
            adminFee: _adminFee,
            minLiquidity: _minLiquidity,
            maxLiquidity: _maxLiquidity,
            enabled: true,
            minWeight: MIN_WEIGHT,
            maxWeight: MAX_WEIGHT
        });
        
        swapFee = SwapFee({
            swapFee: _feeRate,
            adminSwapFee: _adminFee,
            protocolFee: 0
        });
    }

    // Add token to pool
    function addToken(
        address token,
        uint256 weight
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(weight >= poolConfig.minWeight && weight <= poolConfig.maxWeight, "Invalid weight");
        require(poolTokens[token].token == address(0), "Token already added");
        
        poolTokens[token] = PoolToken({
            token: IERC20(token),
            balance: 0,
            weight: weight,
            price: 0,
            lastUpdate: block.timestamp
        });
        
        poolTokenList.push(poolTokens[token]);
        
        emit TokenAdded(token, weight, block.timestamp);
    }

    // Remove token from pool
    function removeToken(address token) external onlyOwner {
        require(poolTokens[token].token != address(0), "Token not found");
        
        // Remove from array
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            if (address(poolTokenList[i].token) == token) {
                poolTokenList[i] = poolTokenList[poolTokenList.length - 1];
                poolTokenList.pop();
                break;
            }
        }
        
        delete poolTokens[token];
        
        emit TokenRemoved(token, block.timestamp);
    }

    // Update pool config
    function updatePoolConfig(
        uint256 feeRate,
        uint256 adminFee,
        uint256 minLiquidity,
        uint256 maxLiquidity
    ) external onlyOwner {
        require(feeRate <= MAX_FEE_RATE, "Fee rate too high");
        require(adminFee <= MAX_FEE_RATE, "Admin fee too high");
        require(minLiquidity <= maxLiquidity, "Invalid liquidity limits");
        
        poolConfig = PoolConfig({
            feeRate: feeRate,
            adminFee: adminFee,
            minLiquidity: minLiquidity,
            maxLiquidity: maxLiquidity,
            enabled: poolConfig.enabled,
            minWeight: poolConfig.minWeight,
            maxWeight: poolConfig.maxWeight
        });
        
        swapFee.swapFee = feeRate;
        swapFee.adminSwapFee = adminFee;
        
        emit PoolConfigUpdated(feeRate, adminFee, minLiquidity, maxLiquidity);
    }

    // Update fees
    function updateFees(
        uint256 swapFeeRate,
        uint256 adminSwapFeeRate,
        uint256 protocolFeeRate
    ) external onlyOwner {
        require(swapFeeRate <= MAX_FEE_RATE, "Swap fee too high");
        require(adminSwapFeeRate <= MAX_FEE_RATE, "Admin fee too high");
        require(protocolFeeRate <= MAX_FEE_RATE, "Protocol fee too high");
        
        swapFee = SwapFee({
            swapFee: swapFeeRate,
            adminSwapFee: adminSwapFeeRate,
            protocolFee: protocolFeeRate
        });
        
        emit FeeUpdated(swapFeeRate, adminSwapFeeRate, protocolFeeRate);
    }

    // Add liquidity
    function addLiquidity(
        uint256[] calldata amounts
    ) external payable nonReentrant {
        require(poolConfig.enabled, "Pool disabled");
        require(amounts.length == poolTokenList.length, "Invalid amounts array");
        
        uint256[] memory tokenAmounts = new uint256[](poolTokenList.length);
        uint256 totalLiquidity = 0;
        uint256[] memory tokenWeights = new uint256[](poolTokenList.length);
        
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(poolTokenList[i].token.balanceOf(msg.sender) >= amounts[i], "Insufficient balance");
            
            poolTokenList[i].token.transferFrom(msg.sender, address(this), amounts[i]);
            poolTokenList[i].balance = poolTokenList[i].balance.add(amounts[i]);
            
            tokenAmounts[i] = amounts[i];
            tokenWeights[i] = poolTokenList[i].weight;
            totalLiquidity = totalLiquidity.add(amounts[i]);
        }
        
        uint256 sharesToMint = totalLiquidity;
        if (totalSupply > 0) {
            sharesToMint = (totalLiquidity * totalSupply) / getTotalValue();
        }
        
        userShares[msg.sender] = userShares[msg.sender].add(sharesToMint);
        totalSupply = totalSupply.add(sharesToMint);
        
        liquidityPositions[msg.sender] = LiquidityPosition({
            liquidityAmount: totalLiquidity,
            tokenAmounts: tokenAmounts,
            lastUpdateTime: block.timestamp,
            weights: tokenWeights,
            totalValue: getTotalValue()
        });
        
        emit LiquidityAdded(msg.sender, address(0), totalLiquidity, sharesToMint, block.timestamp);
    }

    // Remove liquidity
    function removeLiquidity(
        uint256 sharesToRemove
    ) external nonReentrant {
        require(poolConfig.enabled, "Pool disabled");
        require(userShares[msg.sender] >= sharesToRemove, "Insufficient shares");
        
        LiquidityPosition storage position = liquidityPositions[msg.sender];
        uint256[] memory amounts = new uint256[](poolTokenList.length);
        uint256 totalValue = getTotalValue();
        
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            amounts[i] = (position.tokenAmounts[i] * sharesToRemove) / totalSupply;
            poolTokenList[i].balance = poolTokenList[i].balance.sub(amounts[i]);
            poolTokenList[i].token.transfer(msg.sender, amounts[i]);
        }
        
        userShares[msg.sender] = userShares[msg.sender].sub(sharesToRemove);
        totalSupply = totalSupply.sub(sharesToRemove);
        
        emit LiquidityRemoved(msg.sender, address(0), getTotalValue(), sharesToRemove, block.timestamp);
    }

    // Swap tokens
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable nonReentrant {
        require(poolConfig.enabled, "Pool disabled");
        require(tokenIn != tokenOut, "Same tokens");
        require(amountIn > 0, "Amount must be greater than 0");
        require(poolTokens[tokenIn].token.balanceOf(msg.sender) >= amountIn, "Insufficient balance");
        
        // Check if tokens are supported
        require(poolTokens[tokenIn].token != address(0), "Token not supported");
        require(poolTokens[tokenOut].token != address(0), "Token not supported");
        
        // Calculate output amount
        uint256 amountOut = calculateSwapOutput(tokenIn, tokenOut, amountIn);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        
        // Transfer input tokens
        poolTokens[tokenIn].token.transferFrom(msg.sender, address(this), amountIn);
        
        // Transfer output tokens
        poolTokens[tokenOut].token.transfer(msg.sender, amountOut);
        
        // Update balances
        poolTokens[tokenIn].balance = poolTokens[tokenIn].balance.add(amountIn);
        poolTokens[tokenOut].balance = poolTokens[tokenOut].balance.sub(amountOut);
        
        // Calculate fees
        uint256 fee = (amountIn * swapFee.swapFee) / 10000;
        if (fee > 0) {
            poolTokens[tokenIn].token.transfer(owner(), fee);
        }
        
        emit TokenSwapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, fee, block.timestamp);
    }

    // Calculate swap output
    function calculateSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (uint256) {
        PoolToken storage tokenInInfo = poolTokens[tokenIn];
        PoolToken storage tokenOutInfo = poolTokens[tokenOut];
        
        // Simple constant product formula
        uint256 amountInWithFee = amountIn.mul(10000).sub(swapFee.swapFee).div(10000);
        uint256 amountOut = amountInWithFee.mul(tokenOutInfo.balance).div(
            tokenInInfo.balance.add(amountInWithFee)
        );
        
        return amountOut;
    }

    // Get total value
    function getTotalValue() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            total = total.add(poolTokenList[i].balance);
        }
        return total;
    }

    // Get token balance
    function getTokenBalance(address token) external view returns (uint256) {
        return poolTokens[token].balance;
    }

    // Get token weights
    function getTokenWeights() external view returns (uint256[] memory) {
        uint256[] memory weights = new uint256[](poolTokenList.length);
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            weights[i] = poolTokenList[i].weight;
        }
        return weights;
    }

    // Get pool info
    function getPoolInfo() external view returns (
        uint256 totalSupply_,
        uint256[] memory balances,
        uint256[] memory weights,
        PoolConfig memory config,
        SwapFee memory fees
    ) {
        balances = new uint256[](poolTokenList.length);
        weights = new uint256[](poolTokenList.length);
        
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            balances[i] = poolTokenList[i].balance;
            weights[i] = poolTokenList[i].weight;
        }
        
        return (
            totalSupply,
            balances,
            weights,
            poolConfig,
            swapFee
        );
    }

    // Get user position
    function getUserPosition(address user) external view returns (LiquidityPosition memory) {
        return liquidityPositions[user];
    }

    // Get pool tokens
    function getPoolTokens() external view returns (address[] memory) {
        address[] memory tokens = new address[](poolTokenList.length);
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            tokens[i] = address(poolTokenList[i].token);
        }
        return tokens;
    }

    // Get pool stats
    function getPoolStats() external view returns (
        uint256 totalValue,
        uint256 totalSupply_,
        uint256 totalFees,
        uint256[] memory balances
    ) {
        totalValue = getTotalValue();
        totalSupply_ = totalSupply;
        totalFees = 0; // Implementation in future
        
        balances = new uint256[](poolTokenList.length);
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            balances[i] = poolTokenList[i].balance;
        }
        
        return (totalValue, totalSupply_, totalFees, balances);
    }

    // Toggle pool
    function togglePool() external onlyOwner {
        poolConfig.enabled = !poolConfig.enabled;
    }

    // Get max liquidity
    function getMaxLiquidity() external view returns (uint256) {
        return poolConfig.maxLiquidity;
    }

    // Get min liquidity
    function getMinLiquidity() external view returns (uint256) {
        return poolConfig.minLiquidity;
    }
    // Добавить структуру:
struct ConcentratedLiquidity {
    address tokenA;
    address tokenB;
    uint256 lowerPrice;
    uint256 upperPrice;
    uint256 liquidityAmount;
    uint256 fee;
    uint256 lastUpdateTime;
}

// Добавить функции:
function addConcentratedLiquidity(
    address tokenA,
    address tokenB,
    uint256 lowerPrice,
    uint256 upperPrice,
    uint256 amountA,
    uint256 amountB
) external {
    // Добавление концентрированной ликвидности
}

function removeConcentratedLiquidity(
    address tokenA,
    address tokenB,
    uint256 lowerPrice,
    uint256 upperPrice,
    uint256 liquidityAmount
) external {
    // Удаление концентрированной ликвидности
}
}
