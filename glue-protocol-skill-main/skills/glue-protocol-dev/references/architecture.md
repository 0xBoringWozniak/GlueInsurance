# Glue Protocol Architecture

## Lore (Terminology)

| Term | Meaning |
|------|---------|
| **Glue Stick** | Factory contract that clones Glue contracts for specific tokens/NFTs |
| **Sticky Asset** | A token or NFT with an associated Glue (backed by collateral) |
| **Glue** / **Glue Address** | The contract holding collateral for a specific token |
| **Glued Collaterals** | Assets held in a Glue (ETH, USDC, DAI, etc.) |
| **Apply the Glue** | Create a Glue for a token, making it sticky |
| **Unglue** | Burn tokens to withdraw proportional collateral |
| **Glued Loan** | Flash loan borrowing from Glue collateral (single or multi-Glue) |
| **Glued Hooks** | Custom logic executed on unglue (sticky hook + collateral hook) |
| **Sticky Asset Standard** | Contracts to expand Glue functionality |
| **Sticky Asset Native** | Contracts natively compatible with the standard |

## Core Protocol Contracts (V1)

6 contracts + 5 interfaces:
- **GlueStickERC20** — Factory for ERC20 token Glues
- **GlueStickERC721** — Factory for ERC721 Enumerable NFT Glues
- **GlueERC20** — Glue contract for a specific ERC20 token
- **GlueERC721** — Glue contract for a specific ERC721 collection
- **GluedSettings** — Protocol settings management
- **GluedMath** — Math library (512-bit precision, originally from Uniswap team)

Interfaces: IGlueStickERC20, IGlueStickERC721, IGlueERC20, IGlueERC721, IGluedSettings

## Expansion Pack Inheritance Hierarchy

```
GluedConstants (113 lines)
  │ Provides: GLUE_STICK addrs, PRECISION, ETH_ADDRESS, DEAD_ADDRESS
  │
  ├── GluedToolsBase (606 lines) — Full toolkit: ERC20 + ERC721
  │   │ All helpers: nnrtnt, _md512, _transferAsset, _burnAsset, etc.
  │   │
  │   ├── GluedTools (186 lines) — Adds: _batchTransferAsset, _handleExcess
  │   │
  │   └── StickyAsset (760 lines) — Native Glue-compatible token
  │       │ Auto-creates Glue, built-in unglue() + flashLoan()
  │       │ Override hooks for custom logic
  │       │
  │       └── InitStickyAsset (825 lines) — Proxy/factory pattern variant
  │
  └── GluedToolsERC20Base (486 lines) — ERC20-only toolkit (smaller)
      │ Same helpers minus ERC721 handling
      │
      ├── GluedToolsERC20 (137 lines) — Adds batch operations
      │
      └── GluedLoanReceiver (527 lines) — Flash loan strategies
          Has: _approveAsset, _unglueAsset (additional helpers)
```

## Core Mechanics: ERC20 Unglue Flow

### Step-by-step:

1. **`applyTheGlue(token)`** → Creates Glue clone via GlueStick factory, initialized with token
2. **`Glue.initialize(token)`** → Sets STICKY_ASSET, auto-learns token properties:
   - Is it burnable? (has `burn()` function)
   - Does it include `address(0)` in supply? (dead address tracking)
   - Has tax on transfer? (fee-on-transfer detection)
3. **Anyone transfers collateral** to the Glue address (ETH or any ERC20) — no special function needed, just send to the address
4. **Holder calls `unglue(collaterals[], amount, recipient)`:**

```
STEP 1: Transfer tokens from holder to Glue
STEP 2: Detect actual received (handles tax tokens automatically)
STEP 3: Execute sticky hook if enabled (reduces effective amount)
STEP 4: Calculate supplyDelta = realAmount × PRECISION / beforeTotalSupply
STEP 5: Burn or store tokens:
        - Tries burn() first
        - Else transfers to DEAD address (0x...dEaD)
        - Else stores in Glue contract itself
STEP 6: For each collateral:
        share = (balance × supplyDelta / PRECISION) × (1 - 0.1% protocol fee)
STEP 7: Execute collateral hook if enabled (reduces recipient amount)
STEP 8: Split protocol fee: glueFee% to glueFeeAddr, rest to teamAddr
STEP 9: Transfer final amounts to recipient
```

5. **Flash Loan:** borrow from Glue collateral → execute callback → verify repayment + 0.01% fee

### Unglue Function Signature (ERC20):

```solidity
function unglue(
    address[] collaterals,  // Which collateral tokens to withdraw
    uint256 amount,         // How many sticky tokens to burn
    address recipient       // Who receives the collateral (0 = msg.sender)
) external nnrtnt returns (
    uint256 supplyDelta,        // Proportion burned (realAmount × PRECISION / beforeSupply)
    uint256 realAmount,         // Actual tokens burned (after tax detection)
    uint256 beforeTotalSupply,  // Supply before burn
    uint256 afterTotalSupply    // Supply after burn
);
```

### Internal flow:
- `initialization()`: transfers tokens, detects tax, executes sticky hook, calculates supply delta, burns tokens
- `computeCollateral()`: for each collateral → calculate proportional share → apply protocol fee → execute collateral hook → split fee (glue + team) → transfer to recipient

## Core Mechanics: ERC721 Unglue Flow

Same as ERC20 BUT:
- Uses `tokenIds[]` instead of `amount`
- `supplyDelta = nftCount × PRECISION / beforeTotalSupply`
- NFT hooks: sticky hook does **NO transfer** (only tracks burned IDs), collateral hook **DOES transfer**
- Burn tries: `burn(tokenId)`, transfer to DEAD, store in Glue
- `processUniqueTokenIds()`: removes duplicates, verifies ownership, burns NFTs, executes sticky hook

### Unglue Function Signature (ERC721):

```solidity
function unglue(
    address[] collaterals,  // Which collateral tokens to withdraw
    uint256[] tokenIds,     // Which NFT token IDs to burn
    address recipient       // Who receives the collateral (0 = msg.sender)
) external nnrtnt returns (
    uint256 supplyDelta,
    uint256 realAmount,         // Number of unique NFTs burned
    uint256 beforeTotalSupply,
    uint256 afterTotalSupply
);
```

## Non-Burnable Assets

If a sticky token doesn't implement `burn()`, Glue automatically removes from supply in two ways:
1. **Dead Address:** Sends to `0x000000000000000000000000000000000000dEaD`
2. **Store in Glue:** If dead address transfer also fails, stores tokens in the Glue contract itself

This means ANY ERC20 can be backed by Glue, even without a burn function.

## Organic Supply Reduction

When token price drops below backing, arbitrageurs burn tokens → supply decreases. When market recovers, same market cap = higher price per remaining token.

Example: 1M supply, $10 price, $100M mcap:
- 20% supply burned → $10 price only needs $80M mcap
- If $100M mcap recovers → price = $12.50 (+25% gain)
- 50% supply burned + recovery → price = $20 (+100% gain)

## Hook System

Hooks allow custom logic during the unglue process. Two types:

### Sticky Hook (called during token burn phase)
- `_calculateStickyHookSize(amount) → hookSize` — How much to deduct from the effective burn amount
- `_processStickyHook(amount, tokenIds[], recipient)` — Execute custom logic (e.g., send portion to treasury)
- For ERC721: sticky hook does **NO transfer**, only tracks burned IDs

### Collateral Hook (called during collateral distribution phase)
- `_calculateCollateralHookSize(asset, amount) → hookSize` — How much collateral to deduct
- `_processCollateralHook(asset, amount, isETH, recipient)` — Execute custom logic (e.g., route fee to treasury)
- For ERC721: collateral hook **DOES transfer**

## Flash Loans

Two types available:

### ERC3156 Flash Loan (single Glue)
```solidity
flashLoan(collateral, amount, receiver, params) → success
```
- Borrow ERC20 from a single Glue
- Fee: 0.01% (`FLASH_LOAN_FEE = 1e14`)
- Must repay + fee in same transaction

### Glued Loan (multi-Glue)
```solidity
gluedLoan(glues[], collateral, amount, receiver, params)
```
- Borrow from multiple Glues simultaneously
- More flexible, gas-efficient for large borrows
- Aggregated liquidity across the ecosystem

## Key Interfaces

```
IGlueERC20.unglue(collaterals[], amount, recipient) → (supplyDelta, realAmount, beforeSupply, afterSupply)
IGlueERC721.unglue(collaterals[], tokenIds[], recipient) → (supplyDelta, realAmount, beforeSupply, afterSupply)
IGlueStick.applyTheGlue(asset) → glue
IGlueStick.batchUnglue(assets[], amounts[]/tokenIds[][], collaterals[], recipients[])
IGlueStick.gluedLoan(glues[], collateral, amount, receiver, params)
IStickyAsset.unglue(collaterals[], amount, tokenIds[], recipient)
IStickyAsset.flashLoan(collateral, amount, receiver, params)
IGluedHooks.hasHook() → bool
IGluedHooks.hookSize(asset, amount) → size
IGluedHooks.executeHook(asset, amount, tokenIds[], recipient)
IGluedLoanReceiver.executeOperation(glues[], collateral, expectedAmounts[], params) → bool
```

## GlueStick Read Functions

- **`computeGlueAddress(token)`** — Predict Glue address before deployment
- **`checkAndApproveToken(token)`** — Verify token compatibility
- **`isStickyToken(token)`** → `(bool isSticky, address glueAddress)` — Check if token has a Glue
- **`getGlueAddress(token)`** → `address` — Get Glue address for a sticky token

## Glue Read Functions

- **`stickyTokenAddress()`** → `address` — Get the sticky token for this Glue
- **Get adjusted total supply** — Accounts for tokens in dead address and stored in Glue

## Supported Networks

| Network | Chain ID |
|---------|----------|
| Ethereum Mainnet | 1 |
| Base | 8453 |
| Optimism | 10 |
| Sepolia | 11155111 |
| Base Sepolia | 84532 |
| OP Sepolia | 11155420 |

All factory addresses are identical across all chains.
