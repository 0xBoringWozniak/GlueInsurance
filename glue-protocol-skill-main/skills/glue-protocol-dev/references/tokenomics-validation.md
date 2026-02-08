# Tokenomics Validation

## Rule: Always Provide 5+ Math Examples

Every project MUST include at least 5 worked tokenomics examples showing how the economics work. Calculate worst case, best case, and expected case. Show how fees, hooks, supply changes, and arbitrage affect outcomes.

## The Core Formula

```
withdrawal = (tokens_burned / total_supply) * total_collateral * (1 - protocol_fee)
```

Where `protocol_fee = 0.1% = 1e15 / PRECISION`

In Solidity:
```solidity
supplyDelta = _md512(burnAmount, PRECISION, totalSupply);
collateralShare = _md512(glueBalance, supplyDelta, PRECISION);
protocolFee = _md512(collateralShare, PROTOCOL_FEE, PRECISION);
received = collateralShare - protocolFee;
```

## Standard 5 Scenarios

### Scenario 1: Small Burn (Normal User)

**Setup:** Supply = 1,000,000 tokens, Backing = 100 ETH, Burn = 1,000 tokens

```
supplyDelta = 1,000 / 1,000,000 = 0.1% = 1e15
collateralShare = 100 ETH × 0.1% = 0.1 ETH
protocolFee = 0.1 ETH × 0.1% = 0.0001 ETH
received = 0.1 - 0.0001 = 0.0999 ETH

Per token: 0.0999 / 1000 = 0.0000999 ETH
```

### Scenario 2: Large Burn (Whale)

**Setup:** Supply = 1,000,000 tokens, Backing = 100 ETH, Burn = 100,000 tokens (10% of supply)

```
supplyDelta = 100,000 / 1,000,000 = 10% = 1e17
collateralShare = 100 ETH × 10% = 10 ETH
protocolFee = 10 ETH × 0.1% = 0.01 ETH
received = 10 - 0.01 = 9.99 ETH

Per token: 9.99 / 100,000 = 0.0000999 ETH
(Same per-token rate — Glue is mathematically fair regardless of size)
```

### Scenario 3: With 10% Collateral Hook

**Setup:** Supply = 1,000,000, Backing = 100 ETH, Burn = 10,000, Hook = 10% of collateral to treasury

```
supplyDelta = 10,000 / 1,000,000 = 1%
collateralShare = 100 ETH × 1% = 1 ETH
protocolFee = 1 ETH × 0.1% = 0.001 ETH
afterProtocolFee = 1 - 0.001 = 0.999 ETH
hookDeduction = 0.999 × 10% = 0.0999 ETH → goes to treasury
received = 0.999 - 0.0999 = 0.8991 ETH

User gets: 0.8991 ETH (89.91% of share)
Treasury gets: 0.0999 ETH (9.99% of share)
Protocol gets: 0.001 ETH (0.1% fee)
Total out: 0.8991 + 0.0999 + 0.001 = 1.0 ETH ✅ (accounting balanced)
```

### Scenario 4: Multiple Collaterals

**Setup:** Supply = 1,000,000, Backing = 50 ETH + 50,000 USDC, Burn = 10,000

```
supplyDelta = 10,000 / 1,000,000 = 1%

ETH:
  share = 50 × 1% = 0.5 ETH
  fee = 0.5 × 0.1% = 0.0005 ETH
  received = 0.4995 ETH

USDC (6 decimals):
  share = 50,000 × 1% = 500 USDC
  fee = 500 × 0.1% = 0.5 USDC
  received = 499.5 USDC

User receives: 0.4995 ETH + 499.5 USDC
```

### Scenario 5: After Previous Burns (Supply Reduction Effect)

**Setup:** Originally 1,000,000 supply, 100,000 already burned → 900,000 remaining. Backing still ~100 ETH. Burn = 10,000.

```
supplyDelta = 10,000 / 900,000 = 1.111%
collateralShare = 100 × 1.111% = 1.111 ETH
protocolFee = 1.111 × 0.1% = 0.00111 ETH
received = 1.111 - 0.00111 = 1.1099 ETH

Compare to Scenario 1 (burn 10k from 1M):
  Before burns: 0.999 ETH per 10k tokens
  After burns:  1.1099 ETH per 10k tokens
  Gain: +11.1% more ETH per token burned

WHY: Same collateral backing fewer tokens = more per token
This is the organic supply reduction mechanism at work.
```

## Additional Scenarios to Consider

### With Sticky Hook (Token-Side Deduction)

If sticky hook takes 5% of tokens being burned:

```
Burn attempt = 10,000 tokens
Sticky hook takes = 10,000 × 5% = 500 tokens → goes to treasury/lock
Effective burn = 9,500 tokens
supplyDelta calculated on 9,500, not 10,000

Result: user gets proportional share based on 9,500/1,000,000 = 0.95%
vs without hook: 10,000/1,000,000 = 1.0%
```

### Flash Loan Economics

```
Borrow: 10 ETH from Glue
Fee: 10 × 0.01% = 0.001 ETH
Must repay: 10.001 ETH in same transaction

Profit scenario (arbitrage):
  Borrow 10 ETH → Buy cheap token → Burn for 10.5 ETH backing
  Repay 10.001 ETH
  Profit = 10.5 - 10.001 = 0.499 ETH (before gas)
```

## Revenue-to-Glue Math

### How External Revenue Increases Backing

If a dApp sends revenue to the Glue:

```
Initial: 1,000,000 supply, 100 ETH backing → 0.0001 ETH/token floor
Month 1 revenue: 10 ETH → Glue now has 110 ETH → 0.00011 ETH/token (+10%)
Month 2 revenue: 10 ETH → 120 ETH → 0.00012 ETH/token (+20% from start)
Month 6 revenue: 60 ETH total → 160 ETH → 0.00016 ETH/token (+60%)

With burns: If 200k tokens burned over 6 months:
160 ETH / 800,000 supply = 0.0002 ETH/token (+100% from start!)
```

### Why Glue Beats Traditional Staking

| Aspect | Traditional Staking | Glue Backing |
|--------|-------------------|--------------|
| Claim rewards | Manual (gas each time) | Automatic (burn anytime) |
| Fairness | Early/large stakers advantaged | Mathematically proportional always |
| Complexity | Reward rate, epochs, vesting | Simple: burn = share |
| Trust | Admin controls reward pool | Permissionless, no admin |
| Composability | Locked tokens, limited | Tokens remain liquid until burn |
| Gas | Stake + claim + unstake | Single burn transaction |

Example comparison:
```
Staking: Deposit 10k tokens, wait 30 days, claim 0.5 ETH reward, pay gas ×3
Glue: Hold 10k tokens, revenue accumulates in Glue, burn when you want, pay gas ×1
```

## Arbitrage Economics (Self-Balancing)

### Token Below Backing (Undervalued)

```
Token price on DEX: $0.08
Backing per token: $0.10 (calculable on-chain)
Arbitrage:
  1. Buy 10,000 tokens on DEX for $800
  2. Burn for collateral: 10,000 × $0.10 × 0.999 = $999
  3. Profit: $999 - $800 = $199 (24.9% return)
  4. Buying pressure + supply reduction → price rises toward $0.10

Arbitrageurs keep doing this until DEX price ≈ backing price.
No oracle needed — pure economic incentive.
```

### Token Above Backing (Overvalued)

```
Token price on DEX: $0.15
Backing per token: $0.10
No burn arbitrage possible (would lose money burning $0.15 token for $0.10)
BUT: People buy and hold → more trading activity → more collateral accumulates
Backing slowly rises toward market price
```

## Organic Supply Reduction Effect

```
Initial: 1,000,000 supply, $10/token, $10M market cap

20% burned: 800,000 supply
  Same $10M mcap → $12.50/token (+25%)
  Same $8M mcap → $10/token (no change)
  
50% burned: 500,000 supply
  Same $10M mcap → $20/token (+100%)
  Same $5M mcap → $10/token (no change)

Key insight: Supply reduction means LESS market cap needed to sustain price.
Recovery after dips = faster + higher because fewer tokens exist.
```

## Warning Signs (Bad Tokenomics)

| Red Flag | Problem | Fix |
|----------|---------|-----|
| No revenue source to Glue | Backing stays flat, no growth | Add trading fees, protocol revenue, transaction taxes |
| 100% hook deduction | Users get nothing from burn | Cap hooks at reasonable % (5-20%) |
| Infinite mint capability | Dilutes backing per token to zero | Cap supply or make mint = deposit collateral |
| No burn incentive | Nobody unglues, arbitrage broken | Ensure backing > 0 and accessible |
| Circular backing | Token backs itself | Back with EXTERNAL assets (ETH, USDC) |
| Single collateral type | Risk if that asset crashes | Support multiple collaterals |

## Validation Checklist

For every project, verify:
1. ✅ 5+ math examples showing economics at different scales
2. ✅ Worst case calculated (max hooks, low backing, large burns)
3. ✅ Best case calculated (no hooks, high backing, small burns)
4. ✅ Expected case calculated (typical usage pattern)
5. ✅ Revenue source identified and quantified
6. ✅ Arbitrage mechanism explained
7. ✅ Supply reduction effect demonstrated
8. ✅ All participants have economic incentive
9. ✅ No warning signs present (or mitigated)
10. ✅ User understands the math before deploying
