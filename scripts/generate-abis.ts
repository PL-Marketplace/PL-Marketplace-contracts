import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

const contracts = ['PromptNFT', 'PromptMarketplace', 'KeyDistribution'];

async function generateABIs() {
  console.log('Generating ABIs...');
  
  // Compile contracts first
  console.log('Compiling contracts...');
  execSync('npx hardhat compile', { stdio: 'inherit' });
  
  // Extract ABIs from artifacts
  for (const contractName of contracts) {
    const artifactPath = path.join(
      __dirname,
      '..',
      'artifacts',
      'contracts',
      `${contractName}.sol`,
      `${contractName}.json`
    );
    
    if (fs.existsSync(artifactPath)) {
      const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
      const abi = artifact.abi;
      
      // Generate TypeScript file
      const abiName = contractName === 'PromptNFT' ? 'NFT' : 
                      contractName === 'PromptMarketplace' ? 'MARKETPLACE' :
                      'KEY_DISTRIBUTION';
      
      const tsContent = `// Auto-generated ABI for ${contractName}
export const ${abiName}_ABI = ${JSON.stringify(abi, null, 2)} as const;
`;
      
      const outputPath = path.join(
        __dirname,
        '..',
        '..',
        'frontend',
        'src',
        'abi',
        `${abiName}.ts`
      );
      
      fs.writeFileSync(outputPath, tsContent);
      console.log(`Generated ABI for ${contractName}`);
    } else {
      console.error(`Artifact not found for ${contractName}`);
    }
  }
  
  console.log('ABIs generated successfully!');
}

generateABIs().catch(console.error);
