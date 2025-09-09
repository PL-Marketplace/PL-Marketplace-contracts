import { ethers, network } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  console.log("Deploying contracts with category support to:", network.name);
  
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
    // 1. Deploy PromptNFT with category support
    console.log("\n1. Deploying PromptNFT (with categories)...");
    const PromptNFT = await ethers.getContractFactory("PromptNFT");
    const promptNFT = await PromptNFT.deploy();
    await promptNFT.waitForDeployment();
    const promptNFTAddress = await promptNFT.getAddress();
    console.log("PromptNFT deployed to:", promptNFTAddress);
    
    // 2. Deploy PromptMarketplace with category support
    console.log("\n2. Deploying PromptMarketplace (with categories)...");
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
      features: {
        categories: {
          enabled: true,
          list: [
            "Writing",
            "Coding",
            "Marketing",
            "Design",
            "Analysis",
            "Translation",
            "Education",
            "ImageGeneration",
            "Other"
          ]
        }
      }
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
    console.log("\n🏷️ Categories enabled:");
    deploymentInfo.features.categories.list.forEach((cat, index) => {
      console.log(`   ${index}: ${cat}`);
    });
    
    // Update frontend config
    await updateFrontendConfig(deploymentInfo);
    
    // Extract ABIs
    console.log("\n5. Extracting ABIs...");
    await extractABIs();
    
  } catch (error) {
    console.error("Deployment failed:", error);
    throw error;
  }
}

async function updateFrontendConfig(deploymentInfo: any) {
  console.log("\n6. Updating frontend configuration...");
  
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

// Category configuration
export const CATEGORIES = [
  { value: 0, label: "Writing", key: "Writing" },
  { value: 1, label: "Coding", key: "Coding" },
  { value: 2, label: "Marketing", key: "Marketing" },
  { value: 3, label: "Design", key: "Design" },
  { value: 4, label: "Analysis", key: "Analysis" },
  { value: 5, label: "Translation", key: "Translation" },
  { value: 6, label: "Education", key: "Education" },
  { value: 7, label: "Image Generation", key: "ImageGeneration" },
  { value: 8, label: "Other", key: "Other" }
] as const;

export const CATEGORY_ENUM_MAP = {
  Writing: 0,
  Coding: 1,
  Marketing: 2,
  Design: 3,
  Analysis: 4,
  Translation: 5,
  Education: 6,
  ImageGeneration: 7,
  Other: 8
} as const;
`;

  // Ensure directory exists
  const configDir = path.dirname(frontendConfigPath);
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
  }

  fs.writeFileSync(frontendConfigPath, configContent);
  console.log("Frontend config updated at:", frontendConfigPath);
}

async function extractABIs() {
  const contractNames = ['PromptNFT', 'PromptMarketplace', 'KeyDistribution', 'MockUSDC'];
  const abiDir = path.join(__dirname, '..', '..', 'frontend', 'src', 'abi');
  
  // Create ABI directory if it doesn't exist
  if (!fs.existsSync(abiDir)) {
    fs.mkdirSync(abiDir, { recursive: true });
  }
  
  for (const contractName of contractNames) {
    try {
      const artifactPath = path.join(__dirname, '..', 'artifacts', 'contracts', `${contractName}.sol`, `${contractName}.json`);
      
      if (fs.existsSync(artifactPath)) {
        const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
        const abiPath = path.join(abiDir, `${contractName}.json`);
        
        fs.writeFileSync(abiPath, JSON.stringify(artifact.abi, null, 2));
        console.log(`   ✅ Extracted ABI for ${contractName}`);
      } else {
        console.log(`   ⚠️  Artifact not found for ${contractName}`);
      }
    } catch (error) {
      console.error(`   ❌ Error extracting ABI for ${contractName}:`, error);
    }
  }
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
