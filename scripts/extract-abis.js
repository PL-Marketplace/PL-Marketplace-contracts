const fs = require('fs');
const path = require('path');

// Read the compiled artifacts
const contracts = [
  { name: 'PromptNFT', abiName: 'NFT_ABI' },
  { name: 'PromptMarketplace', abiName: 'MARKETPLACE_ABI' },
  { name: 'KeyDistribution', abiName: 'KEY_DISTRIBUTION_ABI' }
];

contracts.forEach(({ name, abiName }) => {
  try {
    // Read the artifact
    const artifactPath = path.join(__dirname, '..', 'artifacts', 'contracts', `${name}.sol`, `${name}.json`);
    const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
    
    // Extract ABI
    const abi = artifact.abi;
    
    // Generate TypeScript content
    const content = `// Auto-generated ABI for ${name}
export const ${abiName} = ${JSON.stringify(abi, null, 2)} as const;
`;
    
    // Write to frontend
    const outputPath = path.join(__dirname, '..', '..', 'frontend', 'src', 'abi', `${abiName.replace('_ABI', '')}.ts`);
    fs.writeFileSync(outputPath, content);
    
    console.log(`✅ Generated ${abiName} at ${outputPath}`);
  } catch (error) {
    console.error(`❌ Error generating ${abiName}:`, error.message);
  }
});

console.log('\nDone! ABIs generated successfully.');
