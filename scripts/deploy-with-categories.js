// Deployment script for updated contracts with categories
const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying PL-NFT Marketplace with Category Support...\n");

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy MockUSDC (for testnet)
  console.log("\n1. Deploying MockUSDC...");
  const MockUSDC = await hre.ethers.getContractFactory("MockUSDC");
  const mockUSDC = await MockUSDC.deploy();
  await mockUSDC.waitForDeployment();
  console.log("MockUSDC deployed to:", await mockUSDC.getAddress());

  // Deploy PromptNFT
  console.log("\n2. Deploying PromptNFT...");
  const PromptNFT = await hre.ethers.getContractFactory("PromptNFT");
  const promptNFT = await PromptNFT.deploy();
  await promptNFT.waitForDeployment();
  console.log("PromptNFT deployed to:", await promptNFT.getAddress());

  // Deploy PromptMarketplace
  console.log("\n3. Deploying PromptMarketplace...");
  const PromptMarketplace = await hre.ethers.getContractFactory("PromptMarketplace");
  const marketplace = await PromptMarketplace.deploy(
    await promptNFT.getAddress(),
    await mockUSDC.getAddress(),
    deployer.address // treasury
  );
  await marketplace.waitForDeployment();
  console.log("PromptMarketplace deployed to:", await marketplace.getAddress());

  // Set marketplace in NFT contract
  console.log("\n4. Setting marketplace in NFT contract...");
  const setMarketplaceTx = await promptNFT.setMarketplace(await marketplace.getAddress());
  await setMarketplaceTx.wait();
  console.log("Marketplace set in NFT contract");

  // Mint some test USDC
  console.log("\n5. Minting test USDC...");
  const mintAmount = hre.ethers.parseUnits("10000", 6); // 10,000 USDC
  await mockUSDC.mint(deployer.address, mintAmount);
  console.log("Minted 10,000 USDC to deployer");

  // Create a test prompt with category
  console.log("\n6. Creating test prompt with category...");
  const testPromptTx = await promptNFT.mintPrompt(
    deployer.address,
    "QmTestEncryptedCID123", // encrypted data CID
    "QmTestPublicMetaCID456", // public metadata CID
    1 // Category.Coding
  );
  await testPromptTx.wait();
  console.log("Test prompt minted with Coding category");

  // Create listing
  console.log("\n7. Creating marketplace listing...");
  const listingTx = await marketplace.createListing(
    1, // tokenId
    hre.ethers.parseUnits("5", 8), // 5 HBAR
    hre.ethers.parseUnits("2", 6), // 2 USDC
    100 // max 100 licenses
  );
  await listingTx.wait();
  console.log("Listing created");

  // Save deployment info
  const deploymentInfo = {
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    contracts: {
      mockUSDC: await mockUSDC.getAddress(),
      promptNFT: await promptNFT.getAddress(),
      marketplace: await marketplace.getAddress(),
    },
    deployer: deployer.address,
    categories: [
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
  };

  const fs = require("fs");
  fs.writeFileSync(
    `deployments/${hre.network.name}-with-categories.json`,
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("\n✅ Deployment complete!");
  console.log("\n📝 Summary:");
  console.log("- MockUSDC:", deploymentInfo.contracts.mockUSDC);
  console.log("- PromptNFT:", deploymentInfo.contracts.promptNFT);
  console.log("- Marketplace:", deploymentInfo.contracts.marketplace);
  console.log("\n🏷️ Categories enabled:", deploymentInfo.categories.join(", "));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
