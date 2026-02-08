# Contract Selection Guide

## Decision Tree

| You Want To... | Use This Contract | Why |
|----------------|-------------------|-----|
| Create a **new token** natively backed by Glue | `StickyAsset` | Standard deployment. Auto-creates Glue, built-in `unglue()` + `flashLoan()`, override hooks for custom logic |
| Create a new token via **proxy/factory pattern** | `InitStickyAsset` | Same as StickyAsset but initialized post-deployment. For upgradeable proxies, clone factories, diamond pattern |
| Build an **app** that interacts with any Glue (ERC20 + ERC721) | `GluedToolsBase` | Full toolkit. All helpers including ERC721 support. Use when your app handles both token types |
| Build an **app** that only works with ERC20 Glues | `GluedToolsERC20Base` | Smaller deployment. Same helpers minus ERC721 handling. Saves gas if you never touch NFTs |
| Need **batch operations** (ERC20 + ERC721) | `GluedTools` | Extends GluedToolsBase with `_batchTransferAsset` and `_handleExcess` |
| Need **batch operations** (ERC20 only) | `GluedToolsERC20` | Extends GluedToolsERC20Base with batch operations |
| Build a **flash loan strategy** | `GluedLoanReceiver` | Purpose-built for flash loans. Has `_approveAsset`, `_unglueAsset`, auto-repayment, multi-Glue borrowing |

## StickyAsset (760 lines)

The main contract for creating new Glue-backed tokens.

### Constructor

```solidity
constructor(
    string memory contractURI,       // Metadata URI for the token
    bool[2] memory fungibleAndHook   // [isFungible, hasHook]
)
```

- `fungibleAndHook[0]` = `true` for ERC20, `false` for ERC721
- `fungibleAndHook[1]` = `true` to enable hooks, `false` for no hooks

**What happens on deployment:**
1. Calls `applyTheGlue()` on GlueStick factory → creates Glue clone
2. Approves Glue to spend tokens (for unglue flow)
3. Sets `GLUE` as immutable address
4. Glue auto-learns token properties (burnable, tax, dead address tracking)

### Core Functions

```solidity
// Holders burn tokens for proportional collateral
unglue(
    address[] collaterals,    // Which collateral tokens to withdraw
    uint256 amount,           // How many tokens to burn (ERC20)
    uint256[] tokenIds,       // Which NFTs to burn (ERC721) — empty for ERC20
    address recipient         // Who receives collateral (0 = msg.sender)
) → (supplyDelta, realAmount, beforeSupply, afterSupply)

// ERC3156 flash loan from this token's Glue
flashLoan(
    address collateral,       // Which collateral to borrow
    uint256 amount,           // How much to borrow
    address receiver,         // Who receives the loan
    bytes params              // Custom data passed to receiver
) → success
```

### Override Hooks (Custom Logic)

Override these to add custom behavior during unglue:

```solidity
// STICKY HOOK — Called during token burn phase
// Return how much to deduct from effective burn amount
_calculateStickyHookSize(uint256 amount) → uint256 hookSize

// Execute your custom logic (e.g., send portion to treasury)
_processStickyHook(uint256 amount, uint256[] tokenIds, address recipient)

// COLLATERAL HOOK — Called during collateral distribution phase
// Return how much collateral to deduct
_calculateCollateralHookSize(address asset, uint256 amount) → uint256 hookSize

// Execute your custom logic (e.g., route fee to treasury)
_processCollateralHook(address asset, uint256 amount, bool isETH, address recipient)
```

**Hook behavior differs for ERC721:**
- Sticky hook does **NO transfer** (only tracks burned IDs)
- Collateral hook **DOES transfer**

### Inherits

All `GluedToolsBase` helpers: `nnrtnt`, `_md512`, `_transferAsset`, `_burnAsset`, `_adjustDecimals`, `_getGlue`, `_initializeGlue`, `_balanceOfAsset`, `_getTokenDecimals`, etc.

## InitStickyAsset (825 lines)

Identical to StickyAsset but for proxy/factory patterns.

### Key Difference

Instead of constructor, uses initializer:

```solidity
function initializeStickyAsset(
    string memory contractURI,
    bool[2] memory fungibleAndHook
) // Creates Glue post-deployment

function isInitialized() → bool

modifier onlyInitialized // Guards functions that require initialization
```

**Use when:** Deploying via CREATE2, clone factories, UUPS proxies, or diamond pattern. The Glue is created after deployment rather than in the constructor.

## GluedToolsBase (606 lines)

Full toolkit for apps interacting with any Glue. Handles both ERC20 and ERC721.

### Key Helpers Available

All helpers listed in `references/helpers.md`. This is the base that `GluedTools` and `StickyAsset` extend.

### When to Use

- Your app needs to interact with existing Glue contracts (not create new tokens)
- You need to handle both ERC20 and ERC721 assets
- You want the full suite of helpers

## GluedToolsERC20Base (486 lines)

Same as GluedToolsBase but **ERC20-only**. Smaller bytecode, less gas.

### When to Use

- Your app only deals with ERC20 tokens (no NFTs)
- Gas optimization matters
- Flash loan receivers (GluedLoanReceiver inherits this)

## GluedTools (186 lines)

Extends GluedToolsBase with batch operations.

### Additional Functions

```solidity
// Transfer tokens to multiple recipients in one call
_batchTransferAsset(
    address token,
    address[] recipients,
    uint256[] amounts,
    uint256[] tokenIDs,
    uint256 total,
    bool fungible
)

// Handle excess tokens (return to sender or route to Glue)
_handleExcess(address token, uint256 amount, address glue)
```

## GluedToolsERC20 (137 lines)

Extends GluedToolsERC20Base with batch operations. ERC20-only version of GluedTools.

## GluedLoanReceiver (527 lines)

Purpose-built for flash loan strategies.

### Core Pattern

```solidity
contract MyStrategy is GluedLoanReceiver {
    // YOUR STRATEGY LOGIC — override this
    function _executeFlashLoanLogic(bytes memory params) 
        internal override returns (bool) 
    {
        // Borrow is already received at this point
        // Do your arbitrage / liquidation / whatever
        // Repayment happens automatically after this returns true
        return true;
    }
}
```

### Functions

```solidity
// Called by protocol — DO NOT override
executeOperation(
    address[] glues,
    address collateral,
    uint256[] expectedAmounts,
    bytes params
) → bool

// Request a loan from multiple Glues at once
_requestGluedLoan(
    bool useERC721,          // false for ERC20 Glues, true for ERC721
    address[] glues,         // Which Glues to borrow from
    address collateral,      // Which collateral token
    uint256 amount,          // Total amount to borrow
    bytes params             // Passed to _executeFlashLoanLogic
)

// Request a loan from a single Glue (simpler)
_requestFlashLoan(
    address glue,            // Which Glue to borrow from
    address collateral,      // Which collateral
    uint256 amount,          // How much
    bytes params             // Passed to _executeFlashLoanLogic
)

// Read current loan state (inside _executeFlashLoanLogic)
getCurrentTotalBorrowed() → uint256    // How much you borrowed
getCurrentCollateral() → address        // What token
getCurrentTotalFees() → uint256         // Fee you must beat (0.01%)
```

### Additional Helpers (beyond GluedToolsERC20Base)

```solidity
_approveAsset(token, spender, amount)   // Safe approve for repayment
_unglueAsset(glue, collaterals, amount) // Unglue tokens within strategy
```

### Inherits

All `GluedToolsERC20Base` helpers: `nnrtnt`, `_md512`, `_transferAsset`, `_burnAsset`, `_adjustDecimals`, plus the loan-specific helpers above.

## Quick Selection Cheat Sheet

```
"I want to make a new backed token"
  → StickyAsset (or InitStickyAsset if proxy pattern)

"I want to build something that sends revenue to existing Glues"
  → GluedToolsBase (ERC20+721) or GluedToolsERC20Base (ERC20 only)

"I want to do airdrops/distributions to many addresses"
  → GluedTools or GluedToolsERC20 (have batch functions)

"I want to build an arbitrage/liquidation bot"
  → GluedLoanReceiver (flash loan built-in)

"I want to build a complex DeFi app touching many Glues"
  → GluedToolsBase + custom logic
```
