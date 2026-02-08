# Glue Insurance MVP

A fully on-chain insurance module for ERC4626 vaults with deterministic loss resolution.

This version uses Glue for the INS token:

- `INSToken` is linked to a dedicated Glue contract via `applyTheGlue`.
- Premium paid by vault is routed into INS Glue collateral.
- INS backing is therefore tied to collateral accumulated in Glue.

## Core Contracts

- `contracts/contracts/InsurancePool.sol`
- `contracts/contracts/INSToken.sol`
- `contracts/contracts/InsuranceRegistry.sol`
- `contracts/contracts/mocks/MockERC4626Vault.sol` (testing)
- `contracts/contracts/MockUSDC.sol` (testing)
- `contracts/contracts/MockGlueStick.sol` + `contracts/contracts/MockGlue.sol` (local testing)

## Flow Overview

### 1) INS token and Glue binding

`INSToken` constructor calls GlueStick:

- production path: official `GLUE_STICK_ERC20` (`0x5fEe29873DE41bb6bCAbC1E4FB0Fc4CB26a7Fd74`)
- local hardhat path: mock override allowed

Result:

- `ins.glue()` returns dedicated Glue contract for INS.

### 2) Insurer liquidity

Insurers deposit USDC into `InsurancePool` and receive INS shares.

- first deposit: `minted = assets`
- later deposits: `minted = assets * totalInsSupply / poolAssetsBeforeDeposit`

Withdraw burns INS and returns proportional USDC from pool.

### 3) Premium routing to Glue

Vault calls:

- `InsurancePool.onPremium(uint256 assets)`

Pool transfers USDC from vault directly to INS Glue:

- `asset.transferFrom(vault, insGlue, assets)`

No INS is minted in premium flow.

### 4) Checkpoint and automatic loss resolution

- `updateCheckpoint()` is permissionless
- baseline PPS can only move up
- minimum interval between checkpoints is 1 day

`triggerLoss()` is permissionless and deterministic:

- validates cooldown
- checks deductible threshold
- computes payout from PPS drawdown
- caps by `min(maxCoverage, poolAssets())`
- transfers payout to vault and caller reward to executor

## Security Properties

- Solidity `^0.8.28`
- `SafeERC20` for token operations
- `ReentrancyGuard` on transfering state-changing paths
- checks-effects-interactions ordering
- no unbounded loops in critical logic

## Test Coverage

`contracts/test/insurance.test.ts` covers:

1. First INS mint
2. Proportional INS mint
3. Withdraw logic
4. Premium increases INS Glue collateral without mint
5. Checkpoint constraints
6. Loss payout correctness
7. Deductible enforcement
8. Caller incentive transfer
9. Cooldown enforcement
10. Insufficient liquidity protection

## Local Run

```bash
cd /Users/anatolijkrestenko/Documents/GlueInsurance/contracts
npm install
npm run build
npm test
npx hardhat run scripts/deploy.ts --network hardhat
```
