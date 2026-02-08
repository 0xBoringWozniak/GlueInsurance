# Helper Functions Reference

## Mandatory Rules

### ❌ NEVER Use

| Bad Pattern | Why It's Bad | Use Instead |
|-------------|-------------|-------------|
| `IERC20(token).transfer(to, amount)` | No tax token handling, no ETH support, unsafe | `_transferAsset` |
| `IERC20(token).transferFrom(from, to, amount)` | No tax detection, doesn't return actual received | `_transferFromAsset` |
| `payable(to).transfer(amount)` | Can fail with 2300 gas limit on contracts | `_transferAsset` with `address(0)` |
| `payable(to).send(amount)` | Same gas limit issue, silent failure | `_transferAsset` with `address(0)` |
| `token.burn(amount)` directly | Doesn't route through Glue properly | `_burnAsset` |
| Manual transfer to `DEAD_ADDRESS` | Skips Glue supply tracking | `_burnAsset` |
| `a * b / c` (raw math) | Overflow risk, precision loss | `_md512(a, b, c)` |
| `a * b / c` rounded up manually | Complex, error-prone | `_md512Up(a, b, c)` |
| `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` | Not Glue standard | `address(0)` for ETH |
| OpenZeppelin `ReentrancyGuard` | Uses storage (expensive gas) | `nnrtnt` modifier (EIP-1153 transient) |

### ✅ ALWAYS Use

| Operation | Helper | Notes |
|-----------|--------|-------|
| Any token transfer | `_transferAsset` | Handles ETH, ERC20, ERC721, tax tokens |
| Transfer with tax detection | `_transferFromAsset` | Returns actual amount received after tax |
| Transfer with balance check | `_transferAssetChecked` | Verifies balance change matches |
| Burn tokens | `_burnAsset` | Burns to Glue (safe, automatic) |
| Burn from specific address | `_burnAssetFrom` | Burns from user to Glue |
| Any multiplication/division | `_md512` | 512-bit precision, prevents overflow |
| Rounded-up division | `_md512Up` | For fees (prevents underpayment) |
| Cross-decimal conversion | `_adjustDecimals` | Converts between different decimal tokens |
| Reentrancy protection | `nnrtnt` modifier | EIP-1153 transient storage (Cancun EVM required) |
| ETH representation | `address(0)` | Always — never the 0xEeee address |

## Complete Helper Reference

### Reentrancy Guard

```solidity
modifier nnrtnt()
```
EIP-1153 transient storage reentrancy guard. Costs ~100 gas vs ~20,000 for storage-based. **Requires Cancun EVM** (`evmVersion: "cancun"` in Hardhat config).

Use on ALL state-changing external/public functions.

### Glue Management

```solidity
// Create a Glue for a token (reverts if already exists or token incompatible)
_initializeGlue(address asset, bool fungible) → address glue

// Try to create a Glue (returns address(0) if already exists, doesn't revert)
_tryInitializeGlue(address asset, bool fungible) → address glue

// Get existing Glue address + check if token is sticky
_getGlue(address asset, bool fungible) → (address glue, bool isSticky)

// Quick check: does this token have a Glue?
_hasAGlue(address asset, bool fungible) → bool
```

**Parameters:**
- `asset` — Token contract address
- `fungible` — `true` for ERC20, `false` for ERC721

### Read Functions

```solidity
// Get balances of multiple collaterals in a Glue
_getGlueBalances(
    address asset,              // The sticky token
    address[] collaterals,      // Which collaterals to check
    bool fungible               // true=ERC20, false=ERC721
) → uint256[] balances

// Get total supply of a sticky token (adjusted for dead/stored tokens)
_getTotalSupply(address asset, bool fungible) → uint256

// Calculate collateral amounts for burning X tokens
_getCollateralbyAmount(
    address asset,              // The sticky token
    uint256 amount,             // How many tokens would be burned
    address[] collaterals,      // Which collaterals to check
    bool fungible               // true=ERC20, false=ERC721
) → uint256[] amounts           // Collateral amounts per token

// Get token balance for any account
_balanceOfAsset(address token, address account, bool fungible) → uint256

// Get NFT owner
_getNFTOwner(address token, uint256 tokenId) → address owner

// Get token decimals
_getTokenDecimals(address token, bool fungible) → uint8 decimals
```

### Transfer Functions

```solidity
// Safe transfer — handles ETH, ERC20, ERC721, and tax tokens
_transferAsset(
    address token,              // Token address (address(0) for ETH)
    address to,                 // Recipient
    uint256 amount,             // Amount (ERC20/ETH) or 0 for NFTs
    uint256[] tokenIDs,         // NFT token IDs (empty array for ERC20)
    bool fungible               // true=ERC20/ETH, false=ERC721
)

// Transfer with tax detection — returns ACTUAL amount received
_transferFromAsset(
    address token,              // Token address
    address from,               // Sender
    address to,                 // Recipient
    uint256 amount,             // Amount requested
    uint256[] tokenIDs,         // NFT token IDs
    bool fungible               // true=ERC20, false=ERC721
) → uint256 actualReceived      // Real amount after tax deduction

// Transfer with post-transfer balance verification
_transferAssetChecked(
    address token,
    address to,
    uint256 amount,
    uint256[] tokenIDs,
    bool fungible
) → uint256 actual              // Verified received amount
```

**Why `_transferAsset` over raw transfer:**
1. Handles ETH natively (checks `token == address(0)`)
2. Detects fee-on-transfer tokens and returns actual received
3. Works for ERC20 AND ERC721 with same interface
4. Safe — doesn't silently fail
5. Gas-efficient — no redundant checks

### Batch Transfer (GluedTools / GluedToolsERC20 only)

```solidity
// Transfer to multiple recipients in one call
_batchTransferAsset(
    address token,
    address[] recipients,       // Array of recipients
    uint256[] amounts,          // Amount per recipient
    uint256[] tokenIDs,         // NFT IDs (for ERC721)
    uint256 total,              // Total amount (for validation)
    bool fungible
)

// Handle leftover tokens (return to sender or route to Glue)
_handleExcess(address token, uint256 amount, address glue)
```

### Burn Functions

```solidity
// Burn tokens to their Glue (safe, automatic)
_burnAsset(
    address token,              // Token to burn
    uint256 amount,             // Amount to burn (ERC20)
    bool fungible,              // true=ERC20, false=ERC721
    uint256[] tokenIDs          // NFT IDs to burn (ERC721)
)

// Burn tokens from a specific address to their Glue
_burnAssetFrom(
    address token,
    address from,               // Address to burn from (must have approved)
    uint256 amount,
    bool fungible,
    uint256[] tokenIDs
)
```

**How `_burnAsset` works internally:**
1. Tries `token.burn(amount)` first
2. If that fails → transfers to `DEAD_ADDRESS` (0x...dEaD)
3. If that also fails → stores in the Glue contract itself
4. ALL methods reduce effective supply — Glue handles all cases

### Math Functions

```solidity
// 512-bit precision multiplication then division (rounds down)
_md512(
    uint256 a,                  // Multiplicand
    uint256 b,                  // Multiplier
    uint256 denominator         // Divisor
) → uint256 result

// Same but rounds UP (use for fees to prevent underpayment)
_md512Up(
    uint256 a,
    uint256 b,
    uint256 denominator
) → uint256 result
```

**Why `_md512` over raw math:**
- `a * b` can overflow uint256 even if the final result fits
- `_md512` uses 512-bit intermediate, preventing overflow
- Based on Uniswap's FullMath library (battle-tested)
- Example: `_md512(1e30, 1e30, 1e18)` = `1e42` ✅ but `1e30 * 1e30 / 1e18` = OVERFLOW ❌

### Decimal Conversion

```solidity
// Convert amount between tokens with different decimals
_adjustDecimals(
    uint256 amount,             // Amount in tokenIn decimals
    address tokenIn,            // Source token
    address tokenOut            // Target token
) → uint256 adjusted            // Amount in tokenOut decimals
```

Example: Converting 1 USDC (6 decimals) to DAI units (18 decimals):
`_adjustDecimals(1e6, USDC, DAI)` → `1e18`

### Flash Loan Helpers (GluedLoanReceiver only)

```solidity
// Approve tokens for repayment
_approveAsset(address token, address spender, uint256 amount)

// Unglue tokens within a flash loan strategy
_unglueAsset(address glue, address[] collaterals, uint256 amount)

// Read current loan state (inside _executeFlashLoanLogic)
getCurrentTotalBorrowed() → uint256     // Total borrowed
getCurrentCollateral() → address         // Collateral token
getCurrentTotalFees() → uint256          // Fee owed (0.01%)
```

## Common Patterns

### Receiving tokens from a user

```solidity
// CORRECT — detects tax tokens
uint256 actual = _transferFromAsset(
    token, msg.sender, address(this), amount, new uint256[](0), true
);
// `actual` may be less than `amount` for tax tokens

// WRONG — doesn't detect tax
IERC20(token).transferFrom(msg.sender, address(this), amount);
```

### Sending ETH

```solidity
// CORRECT
_transferAsset(address(0), recipient, ethAmount, new uint256[](0), true);

// WRONG — gas limit issues
payable(recipient).transfer(ethAmount);
```

### Calculating a 5% fee

```solidity
// CORRECT — 512-bit safe
uint256 fee = _md512(amount, 5e16, PRECISION); // 5e16 = 5%

// CORRECT — rounded up (for protocol fees, ensures minimum payment)
uint256 fee = _md512Up(amount, 5e16, PRECISION);

// WRONG — potential overflow
uint256 fee = amount * 5e16 / 1e18;
```

### Burning tokens to their Glue

```solidity
// CORRECT — handles all edge cases
_burnAsset(token, amount, true, new uint256[](0));

// WRONG — may fail if token not burnable
IERC20(token).burn(amount);
```

## Teaching Reminder

Every time a user needs one of these operations, TEACH the correct helper:
- Explain WHAT it does
- Explain WHY it's better than the raw alternative  
- Show the correct usage pattern
- Warn about the failure mode of the raw alternative
