# GlueInsurance

InsuranceGlue reference implementation:
- `contracts/`: `ERC4626` vault with management/performance fees routed to treasury + insurance pool
- `frontend/`: Next.js dashboard with mocked strategy pools, economics, and history feed

## Contract design

- `InsuranceGlueVault.sol`
  - ERC4626 vault over USDC-like asset
  - Management fee (default `2%` annualized)
  - Performance fee on reported gains (default `20%`)
  - Insurance split from each fee (default `50%` to insurance pool, `50%` treasury)
  - `report(gain, loss)` for strategy accounting simulation

- `InsurancePool.sol`
  - Underwriters stake the same asset
  - Premiums are distributed pro-rata by stake
  - `stake`, `unstake`, `claim`, `pendingPremium`

## Local run

### Contracts

```bash
cd /Users/anatolijkrestenko/Documents/GlueInsurance/contracts
npm install
npm run build
npm test
```

### Frontend

```bash
cd /Users/anatolijkrestenko/Documents/GlueInsurance/frontend
npm install
cp .env.example .env.local
npm run dev
```

## Notes

- This repo is scaffolded from scratch in a clean workspace.
- For production, add role separation (strategist/risk manager/DAO), circuit breakers, and claims logic against realized losses.
