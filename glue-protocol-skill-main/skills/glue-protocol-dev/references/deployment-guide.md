# Deployment Guide

## Hardhat Project Setup (From Scratch)

```bash
mkdir my-project && cd my-project
npm init -y
npm i -D hardhat @nomicfoundation/hardhat-toolbox
npx hardhat init  # → SELECT TYPESCRIPT
npm i @glue-finance/expansions-pack @openzeppelin/contracts
npm i -D dotenv
```

## Hardhat Configuration

```typescript
// hardhat.config.ts
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "cancun",  // ⚠️ REQUIRED for nnrtnt (EIP-1153 transient storage)
    },
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    opSepolia: {
      url: process.env.OP_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    base: {
      url: process.env.BASE_RPC_URL || "https://mainnet.base.org",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    optimism: {
      url: process.env.OP_RPC_URL || "https://mainnet.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      base: process.env.BASESCAN_API_KEY || "",
      baseSepolia: process.env.BASESCAN_API_KEY || "",
      optimisticEthereum: process.env.OPSCAN_API_KEY || "",
    },
  },
};

export default config;
```

**⚠️ CRITICAL:** `evmVersion: "cancun"` is REQUIRED. Without it, the `nnrtnt` reentrancy guard (EIP-1153 transient storage) will not compile or will fail at runtime.

## Environment Setup

Create `.env`:

```bash
# RPC URLs
SEPOLIA_RPC_URL=https://rpc.sepolia.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
OP_SEPOLIA_RPC_URL=https://sepolia.optimism.io
MAINNET_RPC_URL=
BASE_RPC_URL=https://mainnet.base.org
OP_RPC_URL=https://mainnet.optimism.io

# Wallet (NEVER commit this file!)
PRIVATE_KEY=your_private_key_here

# Block explorers (for verification)
ETHERSCAN_API_KEY=
BASESCAN_API_KEY=
OPSCAN_API_KEY=
```

**Add `.env` to `.gitignore` immediately.**

## Step-by-Step Deployment Flow

### Step 1: Compile

```bash
npx hardhat compile
```

Fix any errors. Common issues:
- Missing `evmVersion: "cancun"` → `nnrtnt` won't compile
- Wrong Solidity version → needs `0.8.28`
- Missing imports → check `@glue-finance/expansions-pack` installed

### Step 2: Test

```bash
npx hardhat test
```

Run ALL tests. Fix failures before proceeding. Use `--verbose` for detailed output.

```bash
npx hardhat test --verbose
```

### Step 3: Deploy to Testnet

Create deploy script:

```typescript
// scripts/deploy.ts
import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const Contract = await ethers.getContractFactory("YourContract");
  const contract = await Contract.deploy(/* constructor args */);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("Contract deployed to:", address);
  console.log("Verify with:");
  console.log(`npx hardhat verify --network sepolia ${address} /* constructor args */`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

Deploy:

```bash
npx hardhat run scripts/deploy.ts --network sepolia
```

Save the deployed address — you'll need it for verification and interface integration.

### Step 4: Verify on Block Explorer

```bash
npx hardhat verify --network sepolia CONTRACT_ADDRESS CONSTRUCTOR_ARG1 CONSTRUCTOR_ARG2
```

For StickyAsset with constructor `("uri", [true, false])`:

```bash
npx hardhat verify --network sepolia 0xYourAddress "uri" "[true,false]"
```

If complex constructor args, create a file:

```typescript
// scripts/verify-args.ts
module.exports = [
  "ipfs://your-uri",
  [true, false],
];
```

```bash
npx hardhat verify --network sepolia 0xYourAddress --constructor-args scripts/verify-args.ts
```

### Step 5: Test On-Chain

After deployment, interact via:
- **Etherscan/Basescan:** Go to verified contract → Read/Write Contract
- **Hardhat script:** Write interaction scripts
- **Interface:** Use the frontend you built

Test critical flows:
1. Send collateral to the Glue address
2. Call `unglue()` with small amount
3. Verify collateral received correctly
4. Test hook behavior if applicable
5. Test edge cases (zero, max values)

### Step 6: Deploy to Mainnet

**⚠️ WARNINGS:**
- Gas costs are real money — estimate first with `ethers.estimateGas()`
- Double-check ALL constructor arguments
- Verify contract is fully tested
- Consider multisig ownership (Gnosis Safe) instead of EOA
- Deployment is PERMANENT — no undo

```bash
npx hardhat run scripts/deploy.ts --network mainnet
# or --network base, --network optimism
```

Then verify:

```bash
npx hardhat verify --network mainnet CONTRACT_ADDRESS CONSTRUCTOR_ARGS
```

### Step 7: Post-Deployment

1. **Share deployed addresses** → Integrate into interface
2. **Test on mainnet** with small amounts first
3. **Set up monitoring** → Watch for unexpected behavior
4. **Update README/docs** with deployed addresses

## Supported Networks

| Network | Chain ID | GlueStick ERC20 | GlueStick ERC721 |
|---------|----------|-----------------|------------------|
| Ethereum | 1 | `0x5fEe...Fd74` | `0xe9B0...C257` |
| Base | 8453 | `0x5fEe...Fd74` | `0xe9B0...C257` |
| Optimism | 10 | `0x5fEe...Fd74` | `0xe9B0...C257` |
| Sepolia | 11155111 | `0x5fEe...Fd74` | `0xe9B0...C257` |
| Base Sepolia | 84532 | `0x5fEe...Fd74` | `0xe9B0...C257` |
| OP Sepolia | 11155420 | `0x5fEe...Fd74` | `0xe9B0...C257` |

**All addresses are the same on all chains.**

## Common Deployment Issues

| Issue | Fix |
|-------|-----|
| `nnrtnt` compile error | Add `evmVersion: "cancun"` to Hardhat config |
| "Insufficient funds" | Get testnet ETH from faucet, or add mainnet ETH |
| Verification fails | Check constructor args match exactly, check API key |
| "Already verified" | Contract already verified (success!) |
| "Contract not found" | Wait 1-2 minutes after deployment for block explorer to index |
| Gas estimation fails | Check constructor args are correct, RPC URL is valid |

## Need a Network Not Listed?

Glue Protocol is currently on the networks above. For new network requests, reach out on Discord: discord.gg/ZxqcBxC96w
