// base-liquidity-pool/scripts/deploy.js
const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying Base Liquidity Pool...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());


  const Token1 = await ethers.getContractFactory("ERC20Token");
  const token1 = await Token1.deploy("Token1", "TKN1");
  await token1.deployed();
  
  const Token2 = await ethers.getContractFactory("ERC20Token");
  const token2 = await Token2.deploy("Token2", "TKN2");
  await token2.deployed();


  const LiquidityPool = await ethers.getContractFactory("LiquidityPoolV2");
  const pool = await LiquidityPool.deploy(
    [token1.address, token2.address],
    [5000, 5000], // 50% веса для каждого токена
    10 // 0.1% fee rate
  );

  await pool.deployed();

  console.log("Base Liquidity Pool deployed to:", pool.address);
  console.log("Token1 deployed to:", token1.address);
  console.log("Token2 deployed to:", token2.address);
  
  // Сохраняем адреса
  const fs = require("fs");
  const data = {
    pool: pool.address,
    token1: token1.address,
    token2: token2.address,
    owner: deployer.address
  };
  
  fs.writeFileSync("./config/deployment.json", JSON.stringify(data, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
