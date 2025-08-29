// base-liquidity-pool/test/liquidity-pool.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Base Liquidity Pool", function () {
  let pool;
  let token1;
  let token2;
  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    
    // Деплой токенов
    const Token1 = await ethers.getContractFactory("ERC20Token");
    token1 = await Token1.deploy("Token1", "TKN1");
    await token1.deployed();
    
    const Token2 = await ethers.getContractFactory("ERC20Token");
    token2 = await Token2.deploy("Token2", "TKN2");
    await token2.deployed();
    
    // Деплой Pool контракта
    const LiquidityPool = await ethers.getContractFactory("LiquidityPoolV2");
    pool = await LiquidityPool.deploy(
      [token1.address, token2.address],
      [5000, 5000], // 50% веса для каждого токена
      10 // 0.1% fee rate
    );
    await pool.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await pool.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct parameters", async function () {
      expect(await pool.poolConfig().feeRate).to.equal(10);
      expect(await pool.poolConfig().minLiquidity).to.equal(0);
      expect(await pool.poolConfig().maxLiquidity).to.equal(0);
    });
  });

  describe("Token Management", function () {
    it("Should add a token", async function () {
      await expect(pool.addToken(token1.address, 5000))
        .to.emit(pool, "TokenAdded");
    });
  });

  describe("Liquidity Operations", function () {
    beforeEach(async function () {
      await pool.addToken(token1.address, 5000);
      await pool.addToken(token2.address, 5000);
    });

    it("Should add liquidity", async function () {
      await token1.mint(addr1.address, ethers.utils.parseEther("1000"));
      await token2.mint(addr1.address, ethers.utils.parseEther("1000"));
      
      await token1.connect(addr1).approve(pool.address, ethers.utils.parseEther("1000"));
      await token2.connect(addr1).approve(pool.address, ethers.utils.parseEther("1000"));
      
      await expect(pool.connect(addr1).addLiquidity([
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("100")
      ])).to.emit(pool, "LiquidityAdded");
    });
  });
});
