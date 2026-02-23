


require("dotenv").config();
require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");



const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const BASE_RPC_URL = process.env.BASE_RPC_URL || "https://mainnet.base.org";
const BASE_SEPOLIA_RPC_URL = process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org";

function accounts() {
  return PRIVATE_KEY ? [PRIVATE_KEY] : [];
}

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },

  networks: {
    hardhat: {},
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    baseSepolia: {
      url: BASE_SEPOLIA_RPC_URL,
      accounts: accounts(),
      chainId: 84532
    },
    base: {
      url: BASE_RPC_URL,
      accounts: accounts(),
      chainId: 8453
    }
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || ""
  },

  // Some projects may have different folder structures.

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};
