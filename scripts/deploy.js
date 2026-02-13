const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // Provide TOKEN0 and TOKEN1 or deploy two ERC20-like tokens from PoolManager (if it exists as ERC20 helper)
  let token0 = process.env.TOKEN0 || "";
  let token1 = process.env.TOKEN1 || "";

  if (!token0 || !token1) {
    const Token = await ethers.getContractFactory("PoolManager");
    const t0 = await Token.deploy("Token0", "TK0", 18);
    await t0.deployed();
    const t1 = await Token.deploy("Token1", "TK1", 18);
    await t1.deployed();
    token0 = t0.address;
    token1 = t1.address;
    console.log("Deployed Token0 (PoolManager):", token0);
    console.log("Deployed Token1 (PoolManager):", token1);
  }

  const Pool = await ethers.getContractFactory("LiquidityPool");
  const pool = await Pool.deploy(token0, token1);
  await pool.deployed();

  console.log("LiquidityPool:", pool.address);

  const out = {
    network: hre.network.name,
    chainId: (await ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      Token0: token0,
      Token1: token1,
      LiquidityPool: pool.address
    }
  };

  const outPath = path.join(__dirname, "..", "deployments.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
