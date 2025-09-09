import { ethers } from "hardhat";
import * as dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";

dotenv.config();

// Helper function to convert Hedera address format to EVM format
function convertHederaAddress(hederaAddress: string): string {
  // If already in 0x format, return as is
  if (hederaAddress.startsWith('0x')) {
    return hederaAddress;
  }
  
  // Handle Hedera format (0.0.xxxxx)
  if (hederaAddress.includes('.')) {
    const parts = hederaAddress.split('.');
    if (parts.length === 3) {
      // Convert to EVM address format
      // For testnet USDC: 0.0.456858 -> 0x00000000000000000000000000000000006f99a
      const num = parseInt(parts[2]);
      const hex = num.toString(16);
      return '0x' + hex.padStart(40, '0');
    }
  }
  
  return hederaAddress;
}

async function main() {
  console.log("🚀 Deploying PL-NFT Marketplace to Hedera Testnet...\n");

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatUnits(balance, 8), "HBAR\n");

  // Deploy MockUSDC for testing
  let usdcAddress: string;
  
  if (process.env.HEDERA_TESTNET_USDC) {
    // Convert Hedera format to EVM format
    const hederaUSDC = process.env.HEDERA_TESTNET_USDC;
    usdcAddress = convertHederaAddress(hederaUSDC);
    console.log("Using existing USDC token:");
    console.log("  Hedera format:", hederaUSDC);
    console.log("  EVM format:", usdcAddress);
  } else {
    console.log("Deploying MockUSDC...");
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const mockUSDC = await MockUSDC.deploy(deployer.address);
    await mockUSDC.waitForDeployment();
    usdcAddress = await mockUSDC.getAddress();
    console.log("✅ MockUSDC deployed to:", usdcAddress);
    
    // Mint some USDC for testing
    const mintTx = await mockUSDC.mint(deployer.address, ethers.parseUnits("10000", 6));
    await mintTx.wait();
    console.log("   Minted 10,000 USDC to deployer");
  }

  // Deploy PromptLicenseMarketplace
  console.log("\nDeploying PromptLicenseMarketplace...");
  
  // Use deployer address as treasury if not specified
  const treasuryAddress = process.env.PLATFORM_TREASURY_ADDRESS || deployer.address;
  
  try {
    const PromptMarketplace = await ethers.getContractFactory("PromptMarketplace");
    const marketplace = await PromptMarketplace.deploy(
      "0x0000000000000000000000000000000000000000", // placeholder NFT address, will be set later
      usdcAddress,
      treasuryAddress
    );
    
    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();
    
    console.log("✅ PromptLicenseMarketplace deployed to:", marketplaceAddress);
    console.log("   Platform treasury:", treasuryAddress);
    console.log("   USDC token:", usdcAddress);

    // Save deployment info
    const deployment = {
      network: "hedera-testnet",
      chainId: 296,
      deployer: deployer.address,
      contracts: {
        MockUSDC: usdcAddress,
        PromptLicenseMarketplace: marketplaceAddress
      },
      config: {
        platformTreasury: treasuryAddress,
        platformFeeBps: 250,
        usdcDecimals: 6,
        hbarDecimals: 8
      },
      hedera: {
        rpcUrl: "https://testnet.hashio.io/api",
        mirrorNode: "https://testnet.mirrornode.hedera.com",
        explorerBase: "https://hashscan.io/testnet/contract/",
        marketplaceExplorer: `https://hashscan.io/testnet/contract/${marketplaceAddress}`,
        usdcExplorer: `https://hashscan.io/testnet/contract/${usdcAddress}`
      },
      timestamp: new Date().toISOString()
    };

    const deploymentsDir = path.join(__dirname, "../deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const deploymentPath = path.join(deploymentsDir, "hedera-testnet.json");
    fs.writeFileSync(deploymentPath, JSON.stringify(deployment, null, 2));
    
    console.log("\n📄 Deployment info saved to:", deploymentPath);

    // Create example prompts
    console.log("\n📝 Creating example prompts...");
    await createExamplePrompts(marketplace, deployer.address);

    // Update frontend configuration
    updateFrontendConfig(deployment);

    console.log("\n✨ Deployment complete!");
    console.log("\n📍 View your contracts:");
    console.log(`   - Marketplace: ${deployment.hedera.marketplaceExplorer}`);
    console.log(`   - USDC: ${deployment.hedera.usdcExplorer}`);
    
    console.log("\n🔧 Next steps:");
    console.log("   1. Upload encrypted prompts to IPFS");
    console.log("   2. List prompts on the marketplace");
    console.log("   3. Build frontend to interact with contracts");
    console.log("   4. Set up key exchange mechanism");
    
    console.log("\n💡 Example interaction:");
    console.log("   // List a prompt");
    console.log(`   await marketplace.listPrompt(`);
    console.log(`     ethers.parseUnits("1", 8),  // 1 HBAR`);
    console.log(`     ethers.parseUnits("2", 6),  // 2 USDC`);
    console.log(`     "QmYourEncryptedPromptCID",`);
    console.log(`     "QmYourMetadataCID",`);
    console.log(`     100  // max licenses`);
    console.log(`   );`);
    
  } catch (error) {
    console.error("\n❌ Error during deployment:", error);
    throw error;
  }
}

async function createExamplePrompts(marketplace: any, creator: string) {
  const examples = [
    {
      name: "Advanced Image Generator",
      priceHBAR: ethers.parseUnits("1", 8), // 1 HBAR
      priceUSDC: ethers.parseUnits("2", 6), // 2 USDC
      encryptedCID: "QmExampleEncrypted1",
      metadataCID: "QmExampleMetadata1",
      maxLicenses: 100
    },
    {
      name: "Code Assistant Pro",
      priceHBAR: ethers.parseUnits("2", 8), // 2 HBAR
      priceUSDC: ethers.parseUnits("5", 6), // 5 USDC
      encryptedCID: "QmExampleEncrypted2",
      metadataCID: "QmExampleMetadata2",
      maxLicenses: 0 // Unlimited
    },
    {
      name: "Chemistry Problem Solver",
      priceHBAR: ethers.parseUnits("0.5", 8), // 0.5 HBAR
      priceUSDC: ethers.parseUnits("1", 6), // 1 USDC
      encryptedCID: "QmExampleEncrypted3",
      metadataCID: "QmExampleMetadata3",
      maxLicenses: 50
    }
  ];

  for (let i = 0; i < examples.length; i++) {
    const example = examples[i];
    try {
      console.log(`   Creating "${example.name}"...`);
      
      const tx = await marketplace.listPrompt(
        example.priceHBAR,
        example.priceUSDC,
        example.encryptedCID,
        example.metadataCID,
        example.maxLicenses
      );
      
      const receipt = await tx.wait();
      
      // Find the PromptListed event
      const event = receipt.logs.find((log: any) => {
        try {
          const parsed = marketplace.interface.parseLog(log);
          return parsed?.name === 'PromptListed';
        } catch {
          return false;
        }
      });
      
      if (event) {
        const parsed = marketplace.interface.parseLog(event);
        console.log(`   ✅ Created prompt #${parsed.args[0]} with tx:`, receipt.hash);
      } else {
        console.log(`   ✅ Created with tx:`, receipt.hash);
      }
      
    } catch (error: any) {
      console.log(`   ❌ Failed to create "${example.name}":`, error.message);
    }
  }
}

function updateFrontendConfig(deployment: any) {
  const frontendEnvPath = path.join(__dirname, "../../frontend/.env.local");
  const envContent = `# Hedera Network Configuration
NEXT_PUBLIC_NETWORK=hedera-testnet
NEXT_PUBLIC_CHAIN_ID=296
NEXT_PUBLIC_RPC_URL=${deployment.hedera.rpcUrl}
NEXT_PUBLIC_MIRROR_NODE=${deployment.hedera.mirrorNode}

# Contract Addresses
NEXT_PUBLIC_MARKETPLACE_ADDRESS=${deployment.contracts.PromptLicenseMarketplace}
NEXT_PUBLIC_USDC_ADDRESS=${deployment.contracts.MockUSDC}

# Platform Configuration
NEXT_PUBLIC_PLATFORM_FEE_BPS=${deployment.config.platformFeeBps}

# IPFS Gateway
NEXT_PUBLIC_IPFS_GATEWAY=https://ipfs.io/ipfs/

# API Configuration
NEXT_PUBLIC_API_BASE_URL=http://localhost:3001

# HashConnect Configuration (for wallet connection)
NEXT_PUBLIC_HASHCONNECT_PROJECT_ID=YOUR_PROJECT_ID
`;

  try {
    // Create frontend directory if it doesn't exist
    const frontendDir = path.join(__dirname, "../../frontend");
    if (!fs.existsSync(frontendDir)) {
      fs.mkdirSync(frontendDir, { recursive: true });
    }
    
    fs.writeFileSync(frontendEnvPath, envContent);
    console.log("\n📝 Frontend configuration updated");
  } catch (error) {
    console.log("\n⚠️  Could not update frontend config:", error);
    console.log("   Please create the frontend directory and add the configuration manually");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
