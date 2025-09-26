// base-liquidity-pool/scripts/user-analytics.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function analyzeLiquidityPoolUserBehavior() {
  console.log("Analyzing user behavior for Base Liquidity Pool...");
  
  const poolAddress = "0x...";
  const pool = await ethers.getContractAt("LiquidityPoolV2", poolAddress);
  
  // Анализ пользовательского поведения
  const userAnalytics = {
    timestamp: new Date().toISOString(),
    poolAddress: poolAddress,
    userDemographics: {},
    engagementMetrics: {},
    liquidityPatterns: {},
    userSegments: {},
    recommendations: []
  };
  
  try {
    // Демография пользователей
    const userDemographics = await pool.getUserDemographics();
    userAnalytics.userDemographics = {
      totalUsers: userDemographics.totalUsers.toString(),
      activeUsers: userDemographics.activeUsers.toString(),
      newUsers: userDemographics.newUsers.toString(),
      returningUsers: userDemographics.returningUsers.toString(),
      userDistribution: userDemographics.userDistribution
    };
    
    // Метрики вовлеченности
    const engagementMetrics = await pool.getEngagementMetrics();
    userAnalytics.engagementMetrics = {
      avgSessionTime: engagementMetrics.avgSessionTime.toString(),
      dailyActiveUsers: engagementMetrics.dailyActiveUsers.toString(),
      weeklyActiveUsers: engagementMetrics.weeklyActiveUsers.toString(),
      monthlyActiveUsers: engagementMetrics.monthlyActiveUsers.toString(),
      userRetention: engagementMetrics.userRetention.toString(),
      engagementScore: engagementMetrics.engagementScore.toString()
    };
    
    // Паттерны ликвидности
    const liquidityPatterns = await pool.getLiquidityPatterns();
    userAnalytics.liquidityPatterns = {
      avgLiquidityAmount: liquidityPatterns.avgLiquidityAmount.toString(),
      liquidityFrequency: liquidityPatterns.liquidityFrequency.toString(),
      popularTokens: liquidityPatterns.popularTokens,
      peakLiquidityHours: liquidityPatterns.peakLiquidityHours,
      averageLiquidityPeriod: liquidityPatterns.averageLiquidityPeriod.toString(),
      withdrawalRate: liquidityPatterns.withdrawalRate.toString()
    };
    
    // Сегментация пользователей
    const userSegments = await pool.getUserSegments();
    userAnalytics.userSegments = {
      casualLiquidityProviders: userSegments.casualLiquidityProviders.toString(),
      activeProviders: userSegments.activeProviders.toString(),
      professionalProviders: userSegments.professionalProviders.toString(),
      occasionalUsers: userSegments.occasionalUsers.toString(),
      highValueProviders: userSegments.highValueProviders.toString(),
      segmentDistribution: userSegments.segmentDistribution
    };
    
    // Анализ поведения
    if (parseFloat(userAnalytics.engagementMetrics.userRetention) < 75) {
      userAnalytics.recommendations.push("Low user retention - implement retention strategies");
    }
    
    if (parseFloat(userAnalytics.liquidityPatterns.withdrawalRate) > 25) {
      userAnalytics.recommendations.push("High withdrawal rate - improve user retention");
    }
    
    if (parseFloat(userAnalytics.userSegments.highValueProviders) < 80) {
      userAnalytics.recommendations.push("Low high-value providers - focus on premium user acquisition");
    }
    
    if (userAnalytics.userSegments.casualLiquidityProviders > userAnalytics.userSegments.activeProviders) {
      userAnalytics.recommendations.push("More casual providers than active providers - consider provider engagement");
    }
    
    // Сохранение отчета
    const analyticsFileName = `liquidity-user-analytics-${Date.now()}.json`;
    fs.writeFileSync(`./analytics/${analyticsFileName}`, JSON.stringify(userAnalytics, null, 2));
    console.log(`User analytics report created: ${analyticsFileName}`);
    
    console.log("Liquidity pool user analytics completed successfully!");
    console.log("Recommendations:", userAnalytics.recommendations);
    
  } catch (error) {
    console.error("User analytics error:", error);
    throw error;
  }
}

analyzeLiquidityPoolUserBehavior()
  .catch(error => {
    console.error("User analytics failed:", error);
    process.exit(1);
  });
