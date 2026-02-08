# Glue Insurance MVP

A hackathon-ready, fully on-chain insurance module for ERC4626 vaults.

The system resolves insurance events automatically using deterministic on-chain rules.
There is no governance-based claim resolution and no oracle dependency.
Any address can execute loss resolution and receive a caller incentive.

## Architecture

The MVP contains four core contracts:

- `contracts/contracts/InsurancePool.sol`
- `contracts/contracts/INSToken.sol`
- `contracts/contracts/InsuranceRegistry.sol`
- `contracts/contracts/mocks/MockERC4626Vault.sol` (testing only)

Supporting test token:

- `contracts/contracts/MockUSDC.sol`

## Contract Responsibilities

### InsurancePool

Main insurance engine:

- Holds USDC insurance liquidity
- Accepts insurer deposits and mints INS shares
- Processes insurer withdrawals by burning INS shares
- Receives premium from the vault without minting INS
- Tracks vault PPS checkpoints
- Resolves loss events on-chain in a permissionless way
- Pays a caller reward to the trigger executor

Key state variables:

- `asset` (USDC)
- `vault` (set once)
- `insToken` (set once)
- `premiumRate` (informational)
- `deductible` (1e18 precision)
- `maxCoverage`
- `checkpointPPS`
- `lastCheckpointTs`
- `cooldown`
- `lastTriggerTs`
- `callerRewardBps`

### INSToken

ERC20 insurance share token:

- Minted only by `InsurancePool`
- Burned only by `InsurancePool`
- Represents proportional ownership of insurance pool assets

### InsuranceRegistry

Simple vault-to-pool mapping:

- `registerVault(vault, pool)`
- `getPool(vault)`

### MockERC4626Vault (testing)

Deterministic mock vault with configurable:

- `totalAssets()`
- `totalSupply()`
- Premium transfer into `InsurancePool`

## On-Chain Logic

### Insurer Deposit

`deposit(assets, receiver)`:

- Transfers USDC from user to pool
- Mints INS shares

Minting formula:

- If `insTotalSupply == 0`: `minted = assets`
- Else: `minted = assets * insTotalSupply / poolAssetsBeforeDeposit`

### Insurer Withdraw

`withdraw(insAmount, receiver)`:

- Burns INS from caller
- Sends proportional USDC to receiver

Withdraw formula:

- `assetsOut = insAmount * poolAssets / insTotalSupply`

### Premium Flow

`onPremium(assets)`:

- Callable only by registered vault
- Transfers USDC from vault into pool
- Does not mint INS

Result: premium increases backing per INS token.

### Vault PPS

`pricePerShareVault()`:

- `pps = vault.totalAssets() * 1e18 / vault.totalSupply()`

### Checkpoint Update

`updateCheckpoint()` (permissionless):

- Requires at least 1 day since last checkpoint
- Requires `currentPPS >= checkpointPPS` (baseline cannot decrease)
- Updates baseline and timestamp

### Automatic Loss Resolution

`triggerLoss()` (permissionless):

Requirements:

- Cooldown passed
- Current PPS below deductible threshold

Loss math:

- `lossFraction = (checkpointPPS - currentPPS) * 1e18 / checkpointPPS`
- `payoutWanted = vault.totalAssets() * lossFraction / 1e18`
- `payoutCap = min(maxCoverage, poolAssets)`
- `payout = min(payoutWanted, payoutCap)`

Caller incentive:

- `callerReward = payout * callerRewardBps / 10000`
- `vaultAmount = payout - callerReward`

Transfers:

- USDC to vault (`vaultAmount`)
- USDC to caller (`callerReward`)

State update:

- `lastTriggerTs = block.timestamp`

## Security Notes

- Solidity `^0.8.28`
- Uses `SafeERC20` for all token transfers
- Uses `ReentrancyGuard` on state-changing transfer functions
- Applies checks-effects-interactions ordering
- No unbounded loops in protocol-critical logic

## Tests

Test file:

- `contracts/test/insurance.test.ts`

Covered scenarios:

1. INS minting on first deposit
2. Proportional minting on later deposits
3. Withdraw logic
4. Premium increases pool assets without mint
5. Checkpoint update constraints
6. Loss payout correctness
7. Deductible enforcement
8. Caller reward payment
9. Cooldown enforcement
10. Insufficient liquidity protection

## Deploy

Script:

- `contracts/scripts/deploy.ts`

Deploy order:

1. `MockUSDC`
2. `MockERC4626Vault`
3. `InsurancePool`
4. `INSToken`
5. `InsuranceRegistry`
6. Wire pool/vault/token and register vault-to-pool

## Local Run

```bash
cd /Users/anatolijkrestenko/Documents/GlueInsurance/contracts
npm install
npm run build
npm test
npx hardhat run scripts/deploy.ts --network hardhat
```
