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
// Добавить структуры:
struct PriceRange {
    uint256 lowerBound;
    uint256 upperBound;
    uint256 liquidityAmount;
    uint256 targetPercentage;
    uint256 currentPercentage;
    bool active;
}

struct AutomatedDistribution {
    uint256 poolId;
    address tokenA;
    address tokenB;
    uint256[] priceRanges;
    uint256 lastDistributionTime;
    uint256 distributionFrequency;
    bool enabled;
}


mapping(uint256 => PriceRange[]) public priceRanges;
mapping(uint256 => AutomatedDistribution) public automatedDistributions;


event PriceRangeAdded(
    uint256 indexed poolId,
    uint256 lowerBound,
    uint256 upperBound,
    uint256 targetPercentage
);

event DistributionScheduled(
    uint256 indexed poolId,
    uint256 scheduledTime,
    uint256 frequency
);

event LiquidityDistributed(
    uint256 indexed poolId,
    uint256 amount,
    string range,
    uint256 timestamp
);

// Добавить функции:
function addPriceRange(
    uint256 poolId,
    uint256 lowerBound,
    uint256 upperBound,
    uint256 targetPercentage
) external {
    require(lowerBound < upperBound, "Invalid price range");
    require(targetPercentage <= 10000, "Target percentage too high");
    
    PriceRange memory range = PriceRange({
        lowerBound: lowerBound,
        upperBound: upperBound,
        liquidityAmount: 0,
        targetPercentage: targetPercentage,
        currentPercentage: 0,
        active: true
    });
    
    priceRanges[poolId].push(range);
    
    emit PriceRangeAdded(poolId, lowerBound, upperBound, targetPercentage);
}

function scheduleAutomatedDistribution(
    uint256 poolId,
    uint256 frequency
) external {
    require(frequency > 0, "Frequency must be greater than 0");
    
    automatedDistributions[poolId] = AutomatedDistribution({
        poolId: poolId,
        tokenA: address(0),
        tokenB: address(0),
        priceRanges: new uint256[](0),
        lastDistributionTime: block.timestamp,
        distributionFrequency: frequency,
        enabled: true
    });
    
    emit DistributionScheduled(poolId, block.timestamp, frequency);
}

function distributeLiquidityAutomatically(uint256 poolId) external {
    AutomatedDistribution storage distribution = automatedDistributions[poolId];
    require(distribution.enabled, "Distribution not enabled");
    require(block.timestamp >= distribution.lastDistributionTime + distribution.distributionFrequency, "Too early for distribution");
    
    // Calculate and distribute liquidity
    uint256 totalLiquidity = getTotalLiquidity(poolId);
    
    for (uint256 i = 0; i < priceRanges[poolId].length; i++) {
        PriceRange storage range = priceRanges[poolId][i];
        if (range.active) {
            uint256 amountToDistribute = (totalLiquidity * range.targetPercentage) / 10000;
            range.liquidityAmount += amountToDistribute;
            
            emit LiquidityDistributed(poolId, amountToDistribute, 
                string(abi.encodePacked(range.lowerBound, "-", range.upperBound)), 
                block.timestamp);
        }
    }
    
    distribution.lastDistributionTime = block.timestamp;
}

function getLiquidityDistribution(uint256 poolId) external view returns (PriceRange[] memory) {
    return priceRanges[poolId];
}

function getDistributionInfo(uint256 poolId) external view returns (AutomatedDistribution memory) {
    return automatedDistributions[poolId];
}

function getTotalLiquidity(uint256 poolId) internal view returns (uint256) {
    // Implementation would return total liquidity
    return 0;
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LiquidityPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Существующие структуры и функции...
    
    // Новые структуры для концентрированной ликвидности
    struct ConcentratedLiquidityPosition {
        uint256 positionId;
        address owner;
        address tokenA;
        address tokenB;
        uint256 lowerPrice;
        uint256 upperPrice;
        uint256 liquidityAmount;
        uint256 fee;
        uint256 lastUpdateTime;
        uint256[] tokenAmounts;
        uint256[] priceRanges;
        uint256 allocationWeight;
        bool active;
        uint256 stakedAmount;
        uint256 rewardDebt;
        uint256 earnedRewards;
        uint256 createdAt;
    }
    
    struct PriceRange {
        uint256 lowerBound;
        uint256 upperBound;
        uint256 liquidityAllocation;
        uint256 totalVolume;
        uint256 lastUpdated;
        uint256 currentPrice;
        uint256 allocationWeight;
    }
    
    struct ConcentratedPool {
        address tokenA;
        address tokenB;
        uint256 totalLiquidity;
        uint256 totalStaked;
        uint256 fee;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 accRewardPerShare;
        uint256 poolStartTime;
        uint256 poolEndTime;
        bool isActive;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 priceStep;
        mapping(uint256 => PriceRange) priceRanges;
        uint256[] activePriceRanges;
    }
    
    struct UserConcentratedPosition {
        uint256 positionId;
        address owner;
        uint256 liquidityAmount;
        uint256 rewardDebt;
        uint256 earnedRewards;
        uint256 lastUpdateTime;
        uint256[] stakingHistory;
        uint256 totalRewardsReceived;
        uint256 firstStakeTime;
        uint256 lastClaimTime;
        uint256 pendingRewards;
    }
    
    // Новые маппинги
    mapping(uint256 => ConcentratedLiquidityPosition) public concentratedPositions;
    mapping(address => mapping(address => ConcentratedPool)) public concentratedPools;
    mapping(address => mapping(uint256 => UserConcentratedPosition)) public userConcentratedPositions;
    mapping(address => uint256[]) public userConcentratedPositionsList;
    
    // Новые события
    event ConcentratedLiquidityPositionCreated(
        uint256 indexed positionId,
        address indexed owner,
        address tokenA,
        address tokenB,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 liquidityAmount,
        uint256 createdAt
    );
    
    event ConcentratedLiquidityPositionUpdated(
        uint256 indexed positionId,
        uint256 liquidityAmount,
        uint256 updatedAt
    );
    
    event ConcentratedLiquidityPositionRemoved(
        uint256 indexed positionId,
        address indexed owner,
        uint256 liquidityAmount,
        uint256 removedAt
    );
    
    event PriceRangeUpdated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 rangeId,
        uint256 lowerBound,
        uint256 upperBound,
        uint256 liquidityAllocation,
        uint256 updatedAt
    );
    
    event ConcentratedPoolCreated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 fee,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 priceStep
    );
    
    // Новые функции для концентрированной ликвидности
    function createConcentratedPool(
        address tokenA,
        address tokenB,
        uint256 fee,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 priceStep
    ) external onlyOwner {
        require(tokenA != tokenB, "Same tokens");
        require(minPrice < maxPrice, "Invalid price range");
        require(priceStep > 0, "Invalid price step");
        
        ConcentratedPool storage pool = concentratedPools[tokenA][tokenB];
        pool.tokenA = tokenA;
        pool.tokenB = tokenB;
        pool.fee = fee;
        pool.minPrice = minPrice;
        pool.maxPrice = maxPrice;
        pool.priceStep = priceStep;
        pool.poolStartTime = block.timestamp;
        pool.poolEndTime = block.timestamp + 365 days; // 1 год
        pool.isActive = true;
        
        // Создать диапазоны цен
        uint256 price = minPrice;
        uint256 rangeId = 0;
        while (price < maxPrice) {
            uint256 upperPrice = price + priceStep;
            if (upperPrice > maxPrice) {
                upperPrice = maxPrice;
            }
            
            pool.priceRanges[rangeId] = PriceRange({
                lowerBound: price,
                upperBound: upperPrice,
                liquidityAllocation: 0,
                totalVolume: 0,
                lastUpdated: block.timestamp,
                currentPrice: price + (priceStep / 2),
                allocationWeight: 1000 // 10% веса по умолчанию
            });
            
            pool.activePriceRanges.push(rangeId);
            rangeId++;
            price = upperPrice;
        }
        
        emit ConcentratedPoolCreated(tokenA, tokenB, fee, minPrice, maxPrice, priceStep);
    }
    
    function createConcentratedLiquidityPosition(
        address tokenA,
        address tokenB,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 liquidityAmount,
        uint256[] memory tokenAmounts
    ) external {
        require(concentratedPools[tokenA][tokenB].isActive, "Pool not active");
        require(lowerPrice < upperPrice, "Invalid price range");
        require(liquidityAmount > 0, "Liquidity amount must be greater than 0");
        
        // Проверка, что цена в диапазоне пула
        ConcentratedPool storage pool = concentratedPools[tokenA][tokenB];
        require(lowerPrice >= pool.minPrice && upperPrice <= pool.maxPrice, "Price out of range");
        
        uint256 positionId = uint256(keccak256(abi.encodePacked(tokenA, tokenB, lowerPrice, upperPrice, block.timestamp)));
        
        concentratedPositions[positionId] = ConcentratedLiquidityPosition({
            positionId: positionId,
            owner: msg.sender,
            tokenA: tokenA,
            tokenB: tokenB,
            lowerPrice: lowerPrice,
            upperPrice: upperPrice,
            liquidityAmount: liquidityAmount,
            fee: pool.fee,
            lastUpdateTime: block.timestamp,
            tokenAmounts: tokenAmounts,
            priceRanges: new uint256[](0),
            allocationWeight: 1000, // 10% веса
            active: true,
            stakedAmount: 0,
            rewardDebt: 0,
            earnedRewards: 0,
            createdAt: block.timestamp
        });
        
        // Добавить в список пользователя
        userConcentratedPositionsList[msg.sender].push(positionId);
        
        // Обновить общую ликвидность пула
        pool.totalLiquidity = pool.totalLiquidity.add(liquidityAmount);
        
        emit ConcentratedLiquidityPositionCreated(
            positionId,
            msg.sender,
            tokenA,
            tokenB,
            lowerPrice,
            upperPrice,
            liquidityAmount,
            block.timestamp
        );
    }
    
    function updateConcentratedLiquidityPosition(
        uint256 positionId,
        uint256 newLiquidityAmount
    ) external {
        ConcentratedLiquidityPosition storage position = concentratedPositions[positionId];
        require(position.owner == msg.sender, "Not position owner");
        require(position.active, "Position not active");
        require(newLiquidityAmount > 0, "Liquidity amount must be greater than 0");
        
        // Обновить ликвидность
        ConcentratedPool storage pool = concentratedPools[position.tokenA][position.tokenB];
        pool.totalLiquidity = pool.totalLiquidity.add(newLiquidityAmount).sub(position.liquidityAmount);
        
        position.liquidityAmount = newLiquidityAmount;
        position.lastUpdateTime = block.timestamp;
        
        emit ConcentratedLiquidityPositionUpdated(positionId, newLiquidityAmount, block.timestamp);
    }
    
    function removeConcentratedLiquidityPosition(
        uint256 positionId
    ) external {
        ConcentratedLiquidityPosition storage position = concentratedPositions[positionId];
        require(position.owner == msg.sender, "Not position owner");
        require(position.active, "Position not active");
        
        // Возврат ликвидности
        ConcentratedPool storage pool = concentratedPools[position.tokenA][position.tokenB];
        pool.totalLiquidity = pool.totalLiquidity.sub(position.liquidityAmount);
        
        // Деактивировать позицию
        position.active = false;
        
        emit ConcentratedLiquidityPositionRemoved(
            positionId,
            msg.sender,
            position.liquidityAmount,
            block.timestamp
        );
    }
    
    function addPriceRangeToPool(
        address tokenA,
        address tokenB,
        uint256 lowerBound,
        uint256 upperBound,
        uint256 liquidityAllocation,
        uint256 allocationWeight
    ) external onlyOwner {
        ConcentratedPool storage pool = concentratedPools[tokenA][tokenB];
        require(pool.isActive, "Pool not active");
        require(lowerBound < upperBound, "Invalid price range");
        
        uint256 rangeId = uint256(keccak256(abi.encodePacked(lowerBound, upperBound, block.timestamp)));
        
        pool.priceRanges[rangeId] = PriceRange({
            lowerBound: lowerBound,
            upperBound: upperBound,
            liquidityAllocation: liquidityAllocation,
            totalVolume: 0,
            lastUpdated: block.timestamp,
            currentPrice: (lowerBound + upperBound) / 2,
            allocationWeight: allocationWeight
        });
        
        pool.activePriceRanges.push(rangeId);
        
        emit PriceRangeUpdated(
            tokenA,
            tokenB,
            rangeId,
            lowerBound,
            upperBound,
            liquidityAllocation,
            block.timestamp
        );
    }
    
    function getConcentratedPoolInfo(address tokenA, address tokenB) external view returns (ConcentratedPool memory) {
        return concentratedPools[tokenA][tokenB];
    }
    
    function getConcentratedPositionInfo(uint256 positionId) external view returns (ConcentratedLiquidityPosition memory) {
        return concentratedPositions[positionId];
    }
    
    function getActivePriceRanges(address tokenA, address tokenB) external view returns (uint256[] memory) {
        return concentratedPools[tokenA][tokenB].activePriceRanges;
    }
    
    function getConcentratedPositionByUser(address user, uint256 positionId) external view returns (UserConcentratedPosition memory) {
        return userConcentratedPositions[user][positionId];
    }
    
    function getUserConcentratedPositions(address user) external view returns (uint256[] memory) {
        return userConcentratedPositionsList[user];
    }
    
    function calculateConcentratedLiquidityReward(
        uint256 positionId,
        uint256 timeElapsed
    ) external view returns (uint256) {
        ConcentratedLiquidityPosition storage position = concentratedPositions[positionId];
        if (!position.active || position.liquidityAmount == 0) return 0;
        
        // Простая формула награды
        uint256 baseReward = position.liquidityAmount.mul(timeElapsed).div(1000);
        return baseReward;
    }
    
    function getPoolPriceRanges(address tokenA, address tokenB) external view returns (PriceRange[] memory) {
        ConcentratedPool storage pool = concentratedPools[tokenA][tokenB];
        PriceRange[] memory ranges = new PriceRange[](pool.activePriceRanges.length);
        
        for (uint256 i = 0; i < pool.activePriceRanges.length; i++) {
            ranges[i] = pool.priceRanges[pool.activePriceRanges[i]];
        }
        
        return ranges;
    }
    
    function isPositionInRange(
        uint256 positionId,
        uint256 currentPrice
    ) external view returns (bool) {
        ConcentratedLiquidityPosition storage position = concentratedPositions[positionId];
        return currentPrice >= position.lowerPrice && currentPrice <= position.upperPrice;
    }
    
    function getConcentratedPoolStats(
        address tokenA,
        address tokenB
    ) external view returns (
        uint256 totalLiquidity,
        uint256 totalStaked,
        uint256 totalPositions,
        uint256 activePriceRanges,
        uint256 poolStartTime,
        uint256 poolEndTime
    ) {
        ConcentratedPool storage pool = concentratedPools[tokenA][tokenB];
        return (
            pool.totalLiquidity,
            pool.totalStaked,
            0, // totalPositions - в реальной реализации
            pool.activePriceRanges.length,
            pool.poolStartTime,
            pool.poolEndTime
        );
    }
}
}
