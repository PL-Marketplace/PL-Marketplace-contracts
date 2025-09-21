const hre = require("hardhat");
const fs = require('fs');
const path = require('path');

async function main() {
  console.log("Starting deployment to Hedera testnet...");

  // Get the deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "HBAR");

  // Configuration
  const ADMIN_ADDRESS = deployer.address; // Use deployer as admin for now
  const TREASURY_ADDRESS = deployer.address; // Use deployer as treasury for now
  const ORACLE_ADDRESS = "0x2473fb0154C8f81b32FD5EDBE10E590413b3C436"; // Backend oracle address

  try {
    // 1. Deploy PromptNFT
    console.log("\n1. Deploying PromptNFT...");
    const PromptNFT = await hre.ethers.getContractFactory("PromptNFT");
    const promptNFT = await PromptNFT.deploy(ADMIN_ADDRESS); // Pass admin address to constructor
    await promptNFT.waitForDeployment();
    const nftAddress = await promptNFT.getAddress();
    console.log("PromptNFT deployed to:", nftAddress);

    // 2. Deploy EscrowMarketplace
    console.log("\n2. Deploying EscrowMarketplace...");
    const EscrowMarketplace = await hre.ethers.getContractFactory("EscrowMarketplace");
    const marketplace = await EscrowMarketplace.deploy(
      nftAddress,
      TREASURY_ADDRESS,
      ADMIN_ADDRESS
    );
    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();
    console.log("EscrowMarketplace deployed to:", marketplaceAddress);

    // 3. Grant ORACLE_ROLE to the backend oracle address
    console.log("\n3. Setting up roles...");
    const ORACLE_ROLE = await marketplace.ORACLE_ROLE();
    const tx = await marketplace.grantRole(ORACLE_ROLE, ORACLE_ADDRESS);
    await tx.wait();
    console.log("Granted ORACLE_ROLE to:", ORACLE_ADDRESS);

    // 4. Verify setup
    console.log("\n4. Verifying setup...");
    console.log("- NFT contract address:", nftAddress);
    console.log("- Marketplace contract address:", marketplaceAddress);
    console.log("- Platform treasury:", await marketplace.platformTreasury());
    console.log("- Platform fee (bps):", (await marketplace.platformFeeBps()).toString());
    
    
    console.log("- Oracle has role:", await marketplace.hasRole(ORACLE_ROLE, ORACLE_ADDRESS));

    // 5. Create comprehensive deployment info
    const deploymentInfo = {
      network: "hedera-testnet",
      chainId: 296, // Hedera testnet chain ID
      deployedAt: new Date().toISOString(),
      deployer: deployer.address,
      contracts: {
        PromptNFT: nftAddress,
        EscrowMarketplace: marketplaceAddress
      },
      configuration: {
        admin: ADMIN_ADDRESS,
        treasury: TREASURY_ADDRESS,
        oracle: ORACLE_ADDRESS,
        platformFeeBps: 250,
        hbarDecimals: 8 // Hedera uses 8 decimals, not 18
      },
      roles: {
        ORACLE_ROLE: ORACLE_ROLE,
        ADMIN_ROLE: await marketplace.ADMIN_ROLE(),
        DEFAULT_ADMIN_ROLE: await marketplace.DEFAULT_ADMIN_ROLE()
      },
      abi: {
        PromptNFT: "PromptNFT.json",
        EscrowMarketplace: "EscrowMarketplace.json"
      }
    };

    console.log("\n=== DEPLOYMENT COMPLETE ===");
    console.log(JSON.stringify(deploymentInfo, null, 2));

    // Save deployment info
    const deploymentDir = path.join(__dirname, '../deployments');
    if (!fs.existsSync(deploymentDir)) {
      fs.mkdirSync(deploymentDir, { recursive: true });
    }
    
    // Save timestamped version
    const deploymentPath = path.join(deploymentDir, `deployment-${Date.now()}.json`);
    fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
    console.log("\nDeployment info saved to:", deploymentPath);
    
    // Save latest version
    const latestPath = path.join(deploymentDir, 'latest.json');
    fs.writeFileSync(latestPath, JSON.stringify(deploymentInfo, null, 2));
    console.log("Latest deployment info saved to:", latestPath);

    // Copy ABIs to deployment directory
    console.log("\n5. Copying ABIs...");
    const artifactsDir = path.join(__dirname, '../artifacts/contracts');
    const abiDir = path.join(deploymentDir, 'abi');
    
    if (!fs.existsSync(abiDir)) {
      fs.mkdirSync(abiDir, { recursive: true });
    }

    // Copy PromptNFT ABI
    const nftArtifact = JSON.parse(
      fs.readFileSync(path.join(artifactsDir, 'PromptNFT.sol/PromptNFT.json'), 'utf8')
    );
    fs.writeFileSync(
      path.join(abiDir, 'PromptNFT.json'),
      JSON.stringify(nftArtifact.abi, null, 2)
    );

    // Copy EscrowMarketplace ABI
    const marketplaceArtifact = JSON.parse(
      fs.readFileSync(path.join(artifactsDir, 'EscrowMarketplace.sol/EscrowMarketplace.json'), 'utf8')
    );
    fs.writeFileSync(
      path.join(abiDir, 'EscrowMarketplace.json'),
      JSON.stringify(marketplaceArtifact.abi, null, 2)
    );

    console.log("ABIs copied to:", abiDir);

    // Instructions
    console.log("\n=== NEXT STEPS ===");
    console.log("1. Run the update script to update frontend and backend:");
    console.log("   npm run update-contracts");
    console.log("\n2. Or manually update:");
    console.log("   - Frontend: src/config/contracts.ts");
    console.log("   - Backend: Update contract addresses in .env or config");
    console.log("\n3. Test the deployment with a small transaction");

  } catch (error) {
    console.error("Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
