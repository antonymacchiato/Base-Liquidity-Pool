require("dotenv").config();
const fs = require("fs");

async function main() {
  const depPath = path.join(__dirname, "..", "deployments.json");
  const deployments = JSON.parse(fs.readFileSync(depPath, "utf8"));

  const poolAddr = deployments.contracts.LiquidityPool;
  const token0Addr = deployments.contracts.Token0;
  const token1Addr = deployments.contracts.Token1;

  const [user] = await ethers.getSigners();
  const pool = await ethers.getContractAt("LiquidityPool", poolAddr);
  const t0 = await ethers.getContractAt("PoolManager", token0Addr);
  const t1 = await ethers.getContractAt("PoolManager", token1Addr);

  console.log("Pool:", poolAddr);

  const amt = ethers.utils.parseUnits("100", 18);
  await (await t0.mint(user.address, amt)).wait();
  await (await t1.mint(user.address, amt)).wait();

  await (await t0.approve(poolAddr, amt)).wait();
  await (await t1.approve(poolAddr, amt)).wait();

  await (await t0.transfer(poolAddr, amt)).wait();
  await (await t1.transfer(poolAddr, amt)).wait();

  await (await pool.mint(user.address)).wait();
  console.log("Minted LP");

  await (await pool.sync()).wait();
  console.log("Synced");

  // Send extra and skim
  await (await t0.transfer(poolAddr, ethers.utils.parseUnits("1", 18))).wait();
  await (await pool.skim(user.address)).wait();
  console.log("Skimmed extras");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

