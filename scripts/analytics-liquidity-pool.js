// base-liquidity-pool/scripts/analytics.js
const { ethers } = require("hardhat");

async function analyzePool() {
  console.log("Analyzing Base Liquidity Pool...");
  
  const poolAddress = "0x...";
  const pool = await ethers.getContractAt("LiquidityPoolV2", poolAddress);
  
  // Получение статистики пула
  const poolInfo = await pool.getPoolInfo();
  console.log("Pool Info:", {
    totalSupply: poolInfo.totalSupply.toString(),
    feeRate: poolInfo.feeRate.toString(),
    totalVolume: poolInfo.totalVolume.toString(),
    totalLiquidity: poolInfo.totalLiquidity.toString(),
    poolType: poolInfo.poolType.toString()
  });
  
  // Анализ токенов
  const tokenInfo = await pool.getTokenInfo();
  console.log("Token Info:", {
    token1: tokenInfo.token1,
    token2: tokenInfo.token2,
    reserve1: tokenInfo.reserve1.toString(),
    reserve2: tokenInfo.reserve2.toString()
  });
  
  // Анализ доходности
  const apr = await pool.calculateAPR();
  console.log("APR:", apr.toString());
  
  // Анализ ликвидности
  const liquidityStats = await pool.getLiquidityStats();
  console.log("Liquidity Stats:", {
    totalLiquidity: liquidityStats.totalLiquidity.toString(),
    activePools: liquidityStats.activePools.toString(),
    avgLiquidity: liquidityStats.avgLiquidity.toString()
  });
  
  // Генерация отчета
  const fs = require("fs");
  const report = {
    timestamp: new Date().toISOString(),
    poolAddress: poolAddress,
    analytics: {
      poolInfo: poolInfo,
      tokenInfo: tokenInfo,
      apr: apr.toString(),
      liquidityStats: liquidityStats
    }
  };
  
  fs.writeFileSync("./reports/pool-analytics.json", JSON.stringify(report, null, 2));
  
  console.log("Analytics report generated successfully!");
}

analyzePool()
  .catch(error => {
    console.error("Analytics error:", error);
    process.exit(1);
  });
