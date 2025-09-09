1. Deploying PromptNFT (with categories)...
PromptNFT deployed to: 0xA6A61456192AD55AA6C55094a086cb67577472EF

2. Deploying PromptMarketplace (with categories)...
PromptMarketplace deployed to: 0xDAbb7b3FAe1ce5380aF73912e000b5DFaCe6bB92

3. Deploying KeyDistribution...
KeyDistribution deployed to: 0x173f1F65132c433FF45c47b4291F298D5A774827

# PL-NFT Marketplace Smart Contracts

Smart contracts for the PL-NFT marketplace, supporting deployment on Hedera and Base networks.

## Overview

The marketplace consists of four main contracts:

1. **PromptNFT**: ERC-721 contract for tokenizing AI prompts
2. **PromptMarketplace**: Marketplace for buying/selling prompt licenses with HBAR and USDC payments
3. **KeyDistribution**: Manages encrypted key distribution and dispute resolution using Hedera Consensus Service
4. **MockUSDC**: Test USDC token for development (testnet only)

## Features

- ✅ ERC-721 compliant NFTs for AI prompt tokenization
- ✅ Dual payment system (HBAR and USDC)
- ✅ Platform fees and creator earnings distribution
- ✅ Encrypted prompt storage with key distribution
- ✅ License-based marketplace with unlimited/limited licenses
- ✅ Hedera Consensus Service integration for key management
- ✅ Dispute resolution system for failed key revelations
- ✅ Gas-efficient architecture
- ✅ Comprehensive test coverage

## Quick Start

### 1. Install Dependencies

```bash
cd contracts
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your configuration
```

Required environment variables:
- `PRIVATE_KEY`: Deployment wallet private key
- `HEDERA_ACCOUNT_ID`: Your Hedera account ID (for Hedera networks)

### 3. Compile Contracts

```bash
npm run compile
```

### 4. Deploy Contracts

#### Deploy to Hedera Testnet (Recommended)

```bash
npm run deploy:hedera-testnet
```

#### Deploy to Hedera Mainnet

```bash
npm run deploy:hedera-mainnet
```

#### Alternative Networks

```bash
# Base Sepolia (testnet)
npm run deploy:sepolia

# Base Mainnet
npm run deploy:mainnet
```

## Network Information

### Hedera Networks

| Network | Chain ID | RPC URL | Explorer |
|---------|----------|---------|----------|
| Testnet | 296 | https://testnet.hashio.io/api | https://hashscan.io/testnet |
| Mainnet | 295 | https://mainnet.hashio.io/api | https://hashscan.io/mainnet |

### Why Hedera?

1. **Low Fees**: Predictable, USD-based fees (~$0.0001 per transaction)
2. **Fast Finality**: 3-5 second transaction finality
3. **Carbon Negative**: Environmentally sustainable
4. **EVM Compatible**: Deploy standard Solidity contracts
5. **Enterprise Grade**: Used by Google, IBM, and others

## Contract Architecture

```
PromptNFT
├── Minting AI prompts as NFTs
├── Encrypted and public metadata storage
├── Creator token tracking
├── Marketplace approval system
└── IPFS URI management

PromptMarketplace
├── License-based marketplace
├── Dual payment system (HBAR/USDC)
├── Platform fee collection (2.5%)
├── Creator earnings distribution
├── License tracking and limits
└── Emergency pause functionality

KeyDistribution
├── Commit-reveal key system
├── Hedera Consensus Service integration
├── Dispute resolution for missing keys
├── Refund management
└── 24h reveal deadline enforcement

MockUSDC
├── ERC-20 test token (6 decimals)
├── Owner-only minting
└── Faucet function for testing
```

## Marketplace Flow

1. **Prompt Creation**: Creator mints a PromptNFT with encrypted content and public metadata
2. **Key Commitment**: Creator commits to an encryption key hash for the prompt
3. **Marketplace Listing**: Creator lists the NFT on PromptMarketplace with HBAR/USDC prices
4. **License Purchase**: Buyers purchase licenses and receive access rights
5. **Key Revelation**: Creator reveals the encryption key via Hedera Consensus Service
6. **Dispute Resolution**: If key isn't revealed within 24h, buyers can raise disputes for refunds

## Testing

Run the test suite:

```bash
npm test
```

## Gas Optimization

The contracts are optimized for gas efficiency:
- Minimal storage operations
- Efficient data packing
- Optimized loops and conditions

## Security Considerations

- Owner-only functions for critical operations
- Reentrancy guards on payment functions
- Input validation and sanity checks
- Follows OpenZeppelin best practices

## Deployment Costs

Estimated deployment costs:

| Network | PromptNFT | PromptMarketplace | KeyDistribution | MockUSDC | Total USD |
|---------|-----------|-------------------|----------------|----------|-----------|
| Hedera | ~5 HBAR | ~8 HBAR | ~6 HBAR | ~3 HBAR | ~$1.10 |
| Base | ~0.005 ETH | ~0.008 ETH | ~0.006 ETH | ~0.003 ETH | ~$55 |

## Post-Deployment

After deployment:

1. Contract addresses are saved to `deployments/[network].json`
2. Frontend `.env.local` is automatically updated
3. Verify contracts on block explorer
4. Configure backend with contract addresses

## Future Enhancements

### Enhanced Key Distribution
- Multi-party key distribution for improved security
- Time-locked key revelation
- Automated dispute arbitration

### Advanced Marketplace Features
- Auction system for rare prompts
- Subscription-based license models
- Royalty splits for collaborative prompts

### Cross-Chain Expansion
- Bridge integration for multi-chain deployment
- Cross-chain license portability
- Unified marketplace across networks

### Hedera Services Integration
- Hedera Token Service for native tokens
- Enhanced Consensus Service for audit trails
- Hedera File Service for metadata redundancy

## Support

- Documentation: [Link to docs]
- Discord: [Link to Discord]
- Issues: [GitHub Issues]

## License

MIT License - see LICENSE file for details