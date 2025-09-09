import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  console.log("Deploying contracts to:", network.name);
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  
  // Get account balance
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "HBAR");
  
  // Platform treasury (same as deployer for testnet)
  const PLATFORM_TREASURY = deployer.address;
  
  // USDC address on Hedera testnet
  const USDC_ADDRESS = "0x000000000000000000000000000000000006f89a";
  
  try {
    // 1. Deploy PromptNFT
    console.log("\n1. Deploying PromptNFT...");
    const PromptNFT = await ethers.getContractFactory("PromptNFT");
    const promptNFT = await PromptNFT.deploy();
    await promptNFT.waitForDeployment();
    const promptNFTAddress = await promptNFT.getAddress();
    console.log("PromptNFT deployed to:", promptNFTAddress);
    
    // 2. Deploy PromptMarketplace
    console.log("\n2. Deploying PromptMarketplace...");
    const PromptMarketplace = await ethers.getContractFactory("PromptMarketplace");
    const marketplace = await PromptMarketplace.deploy(
      promptNFTAddress,
      USDC_ADDRESS,
      PLATFORM_TREASURY
    );
    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();
    console.log("PromptMarketplace deployed to:", marketplaceAddress);
    
    // 3. Deploy KeyDistribution
    console.log("\n3. Deploying KeyDistribution...");
    const KeyDistribution = await ethers.getContractFactory("KeyDistribution");
    const keyDistribution = await KeyDistribution.deploy();
    await keyDistribution.waitForDeployment();
    const keyDistributionAddress = await keyDistribution.getAddress();
    console.log("KeyDistribution deployed to:", keyDistributionAddress);
    
    // 4. Configure contracts
    console.log("\n4. Configuring contracts...");
    
    // Set marketplace in PromptNFT
    console.log("Setting marketplace in PromptNFT...");
    const setMarketplaceTx = await promptNFT.setMarketplace(marketplaceAddress);
    await setMarketplaceTx.wait();
    console.log("Marketplace set in PromptNFT");
    
    // Save deployment info
    const deploymentInfo = {
      network: network.name,
      chainId: network.config.chainId,
      contracts: {
        PromptNFT: {
          address: promptNFTAddress,
          deployer: deployer.address,
          deploymentBlock: promptNFT.deploymentTransaction()?.blockNumber || 0,
        },
        PromptMarketplace: {
          address: marketplaceAddress,
          deployer: deployer.address,
          deploymentBlock: marketplace.deploymentTransaction()?.blockNumber || 0,
        },
        KeyDistribution: {
          address: keyDistributionAddress,
          deployer: deployer.address,
          deploymentBlock: keyDistribution.deploymentTransaction()?.blockNumber || 0,
        },
        USDC: {
          address: USDC_ADDRESS,
        },
      },
      platformTreasury: PLATFORM_TREASURY,
      deploymentTimestamp: new Date().toISOString(),
    };
    
    // Save to file
    const deploymentsDir = path.join(__dirname, "..", "deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir);
    }
    
    const deploymentPath = path.join(deploymentsDir, `${network.name}.json`);
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    
    console.log("\n✅ Deployment complete!");
    console.log("📄 Deployment info saved to:", deploymentPath);
    
    // Update frontend config
    await updateFrontendConfig(deploymentInfo);
    
  } catch (error) {
    console.error("Deployment failed:", error);
    throw error;
  }
}

async function updateFrontendConfig(deploymentInfo: any) {
  console.log("\n5. Updating frontend configuration...");
  
  const frontendConfigPath = path.join(__dirname, "..", "..", "frontend", "src", "config", "contracts.ts");
  
  const configContent = `// Auto-generated contract configuration
export const CONTRACTS = {
  NFT: "${deploymentInfo.contracts.PromptNFT.address}",
  MARKETPLACE: "${deploymentInfo.contracts.PromptMarketplace.address}",
  KEY_DISTRIBUTION: "${deploymentInfo.contracts.KeyDistribution.address}",
  USDC: "${deploymentInfo.contracts.USDC.address}",
} as const;

export const DEPLOYMENT_BLOCK = {
  NFT: ${deploymentInfo.contracts.PromptNFT.deploymentBlock || 0},
  MARKETPLACE: ${deploymentInfo.contracts.PromptMarketplace.deploymentBlock || 0},
  KEY_DISTRIBUTION: ${deploymentInfo.contracts.KeyDistribution.deploymentBlock || 0},
} as const;

export const PLATFORM_TREASURY = "${deploymentInfo.platformTreasury}";

export const NETWORK_CONFIG = {
  chainId: ${deploymentInfo.chainId},
  network: "${deploymentInfo.network}",
} as const;
`;

  fs.writeFileSync(frontendConfigPath, configContent);
  console.log("Frontend config updated at:", frontendConfigPath);
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
