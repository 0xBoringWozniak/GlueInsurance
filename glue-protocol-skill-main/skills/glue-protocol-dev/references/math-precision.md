# Math & Precision System

## The PRECISION System

`PRECISION = 1e18` represents **100%**. All percentages in Glue Protocol are expressed as fractions of PRECISION.

### Percentage Table

| Percentage | Value | Expression |
|-----------|-------|------------|
| 100% | `1e18` | `PRECISION` |
| 50% | `5e17` | `PRECISION / 2` |
| 25% | `25e16` | `PRECISION / 4` |
| 10% | `1e17` | `PRECISION / 10` |
| 5% | `5e16` | |
| 2.5% | `25e15` | |
| 1% | `1e16` | |
| 0.5% | `5e15` | |
| 0.1% | `1e15` | `PROTOCOL_FEE` |
| 0.05% | `5e14` | |
| 0.01% | `1e14` | `FLASH_LOAN_FEE` |
| 0.001% | `1e13` | |

### Protocol Constants

| Constant | Value | Percentage |
|----------|-------|-----------|
| `PRECISION` | `1e18` | 100% (denominator for all math) |
| `PROTOCOL_FEE` | `1e15` | 0.1% (unglue fee) |
| `FLASH_LOAN_FEE` | `1e14` | 0.01% (flash loan fee) |

## `_md512` — The Core Math Function

```solidity
_md512(uint256 a, uint256 b, uint256 denominator) → uint256 result
```

Performs `(a × b) / denominator` using 512-bit intermediate precision. Rounds **down**.

```solidity
_md512Up(uint256 a, uint256 b, uint256 denominator) → uint256 result
```

Same calculation but rounds **up**. Use for fees to prevent underpayment.

### Why Not Raw Math?

```solidity
// DANGEROUS — overflows at a * b even if final result fits in uint256
uint256 result = a * b / c;

// Example that OVERFLOWS:
uint256 a = 1e30;
uint256 b = 1e30;
uint256 c = 1e18;
// a * b = 1e60 → EXCEEDS uint256 max (1.15e77) ... wait, this fits
// But: a = 1e40, b = 1e40, c = 1e18 → a * b = 1e80 → OVERFLOW!
// _md512 handles this correctly with 512-bit intermediate

// SAFE — always works
uint256 result = _md512(a, b, c);
```

Even if `a * b` would overflow uint256, `_md512` computes it safely using 512-bit intermediate math (based on Uniswap's FullMath / GluedMath library).

## Common Calculation Patterns

### Calculate a Percentage Fee

```solidity
// 5% fee on amount
uint256 fee = _md512(amount, 5e16, PRECISION);
uint256 afterFee = amount - fee;

// 0.1% protocol fee (what Glue charges)
uint256 protocolFee = _md512(amount, PROTOCOL_FEE, PRECISION);

// Round UP for fees (ensures minimum payment, protects protocol)
uint256 feeUp = _md512Up(amount, 5e16, PRECISION);
```

### Calculate Proportional Share (Unglue Math)

```solidity
// How much collateral does burning `burnAmount` tokens give?
// supplyDelta = burnAmount * PRECISION / totalSupply
uint256 supplyDelta = _md512(burnAmount, PRECISION, totalSupply);

// collateral share = glueBalance * supplyDelta / PRECISION
uint256 share = _md512(glueBalance, supplyDelta, PRECISION);

// After protocol fee (0.1%)
uint256 afterFee = share - _md512(share, PROTOCOL_FEE, PRECISION);
```

### Calculate Token Price from Backing

```solidity
// Price per token = total collateral / total supply
// (use _md512 to maintain precision)
uint256 pricePerToken = _md512(totalCollateral, 1e18, totalSupply);
// Result is in 18-decimal fixed point

// For tokens with different decimals, adjust first:
uint256 adjustedCollateral = _adjustDecimals(collateralAmount, collateralToken, stickyToken);
```

### Supply Delta Calculation

```solidity
// The core Glue formula: what proportion of supply is being burned?
uint256 supplyDelta = _md512(realAmount, PRECISION, beforeTotalSupply);

// This means: "realAmount is supplyDelta/PRECISION of total supply"
// Example: burn 10,000 of 1,000,000 supply
// supplyDelta = _md512(10000e18, 1e18, 1000000e18) = 1e16 (= 1%)
```

## Worked Examples

### Example 1: Simple Unglue

Supply = 1,000,000 tokens, Backing = 100 ETH, Burn = 10,000 tokens

```
supplyDelta = _md512(10000e18, 1e18, 1000000e18) = 1e16 (1%)
collateralShare = _md512(100e18, 1e16, 1e18) = 1e18 (1 ETH)
protocolFee = _md512(1e18, 1e15, 1e18) = 1e15 (0.001 ETH)
received = 1e18 - 1e15 = 999000000000000000 (0.999 ETH)
```

### Example 2: With 10% Collateral Hook

Same as above, but contract takes 10% of collateral via hook.

```
collateralShare = 1 ETH (same)
protocolFee = 0.001 ETH (same)
afterProtocolFee = 0.999 ETH
hookSize = _md512(0.999e18, 1e17, 1e18) = 0.0999 ETH (10%)
received = 0.999 - 0.0999 = 0.8991 ETH
hookTreasury = 0.0999 ETH
```

### Example 3: Multiple Collaterals

Supply = 1,000,000, Backing = 50 ETH + 50,000 USDC, Burn = 10,000

```
supplyDelta = 1e16 (1%)

ETH share = _md512(50e18, 1e16, 1e18) = 5e17 (0.5 ETH)
ETH fee = _md512(5e17, 1e15, 1e18) = 5e14 (0.0005 ETH)
ETH received = 0.4995 ETH

USDC share = _md512(50000e6, 1e16, 1e18) = 500000 (500 USDC, 6 decimals)
USDC fee = _md512(500000, 1e15, 1e18) = 500 (0.0005 USDC)
USDC received = 499.5 USDC (499500000 in 6-decimal)
```

### Example 4: After Supply Reduction

Original: 1,000,000 supply, 100 ETH backing
After burns: 900,000 supply remains, still 100 ETH backing (fees add tiny amount)

```
Burn 10,000 of 900,000:
supplyDelta = _md512(10000e18, 1e18, 900000e18) = 1.111e16 (~1.11%)
collateralShare = _md512(100e18, 1.111e16, 1e18) = 1.111e18 (1.111 ETH)

// MORE per token because supply is smaller!
// Was 0.999 ETH per 10k, now 1.11 ETH per 10k
```

## Decimal Handling

### `_adjustDecimals`

```solidity
_adjustDecimals(uint256 amount, address tokenIn, address tokenOut) → uint256
```

Converts amount from `tokenIn` decimal space to `tokenOut` decimal space.

```solidity
// 1 USDC (6 decimals) → DAI units (18 decimals)
_adjustDecimals(1e6, USDC, DAI) → 1e18

// 1 DAI (18 decimals) → USDC units (6 decimals)
_adjustDecimals(1e18, DAI, USDC) → 1e6

// Same decimals → no change
_adjustDecimals(1e18, WETH, DAI) → 1e18
```

**Always use when comparing or calculating between tokens with different decimals.**

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `amount * fee / PRECISION` | Overflow if amount × fee > uint256 max | `_md512(amount, fee, PRECISION)` |
| `amount / totalSupply * collateral` | Loss of precision (integer division truncates) | `_md512(amount, collateral, totalSupply)` |
| Using `1e17` as PRECISION | All math off by 10x | Always `1e18` |
| Forgetting to adjust decimals | USDC (6) vs DAI (18) = 1e12 difference | `_adjustDecimals` |
| Not rounding up fees | Protocol/hook gets 0 on small amounts | `_md512Up` for fees |
| Division by zero | totalSupply = 0 after all burned | Check `require(totalSupply > 0)` before math |
