# Glue Insurance MVP

A fully on-chain insurance module for ERC4626 vaults with deterministic loss resolution.

This architecture uses a Glue-native INS token:

- INS is linked to Glue via `applyTheGlue`.
- User deposits are routed to INS Glue collateral.
- Premium is routed to INS Glue collateral, increasing INS NAV.
- Loss execution mints INS to protocol, immediately unglues, then pays ERC4626 vault.

## Core Contracts

- `contracts/contracts/InsurancePool.sol`
- `contracts/contracts/INSToken.sol`
- `contracts/contracts/InsuranceRegistry.sol`
- `contracts/contracts/mocks/MockERC4626Vault.sol` (testing)
- `contracts/contracts/MockUSDC.sol` (testing)
- `contracts/contracts/MockGlueStick.sol` + `contracts/contracts/MockGlue.sol` (local testing)

## Flow Overview

### 1) InsurancePool links ERC4626 vault and INS Glue token

- Owner sets vault once with `setVault`.
- Owner sets INS token once with `setINSToken`.
- Pool reads `ins.glue()` and stores INS Glue address.

### 2) Users deposit and receive INS tokens, collateral goes to Glue

`deposit(assets, receiver)`:

- Transfers USDC from user directly to `insGlue`.
- Mints INS to user.
- Minting is proportional to current INS NAV:
  - first deposit: `insMinted = assets`
  - otherwise: `insMinted = assets * totalSupply / glueCollateralBefore`

### 3) Strategy premium increases INS NAV

`onPremium(assets)` (only vault):

- Transfers USDC from vault directly to `insGlue`.
- No INS minting.
- Collateral per INS increases.

### 4) Automatic loss resolution

`triggerLoss()` is permissionless and deterministic:

- Verifies cooldown.
- Computes PPS drawdown against checkpoint and deductible.
- Computes payout target and caps by:
  - `maxCoverage`
  - available collateral in Glue.
- Mints extra INS to pool for required payout size.
- Immediately unglues minted INS to USDC.
- Sends USDC to vault and caller incentive to executor.

### 5) User redeem path

`redeem(insAmount, receiver)`:

- Pulls INS from user.
- Immediately unglues INS to selected collateral (USDC in this MVP).
- Transfers USDC to receiver.

## Security Properties

- Solidity `^0.8.28`
- `SafeERC20` for all token operations
- Reentrancy protection on state-changing external paths
- Deterministic formulas for payout and checkpoint logic
- No unbounded loops in protocol-critical logic
- Math uses `_md512`/`_md512Up` helper style

## Test Coverage

`contracts/test/insurance.test.ts` covers:

1. INS minting on first deposit
2. Proportional minting after NAV change
3. Redeem logic
4. Premium increases INS Glue collateral without mint
5. Checkpoint constraints
6. Loss payout correctness
7. Deductible enforcement
8. Caller incentive transfer
9. Cooldown enforcement
10. Insufficient liquidity protection

## Local Run

```bash
npm install
npm run build
npm test
npx hardhat run scripts/deploy.ts --network hardhat
```
