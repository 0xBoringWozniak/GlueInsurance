# On-Chain vs Off-Chain Decision Framework

## Core Principle

**ALWAYS interpret the user's idea as on-chain first.** Only fall back to oracles or off-chain when truly necessary.

Think: Can Glue collateral ratios provide this? Can users input data? Can events trigger it? Can math derive it?

## Decision Flow

```
User describes idea
  │
  ├─ Can it work fully on-chain?
  │   ├─ YES → Build it on-chain ✅
  │   └─ NO → Needs external data?
  │       ├─ YES → Stage 2: Oracle evaluation
  │       └─ NO → Needs automation/computation?
  │           ├─ YES → Stage 3: Off-chain evaluation
  │           └─ NO → Re-evaluate — probably CAN be on-chain
```

## Stage 1: Fully On-Chain Solutions

### What CAN be done on-chain

| Need | On-Chain Solution |
|------|------------------|
| Token price relative to backing | Glue collateral ratio (backing / supply) |
| Proportional distribution | Glue math (automatic) |
| Vesting/time locks | `block.timestamp` + mapping |
| Voting/governance | On-chain votes with token balances |
| Random selection | Commit-reveal scheme, VRF |
| Conditional transfers | `require()` + state checks |
| Scheduled releases | Anyone-can-call with time check |
| Revenue sharing | Route to Glue (burn for share) |
| Auctions | On-chain bidding with escrow |
| Escrow/multisig | Multi-party approve pattern |

### Glue-Specific On-Chain Data

The Glue protocol provides valuable on-chain data without oracles:

```solidity
// Token backing per unit (price floor)
uint256 backingPerToken = _md512(glueBalance, PRECISION, totalSupply);

// Total collateral in a Glue
uint256 totalBacking = _getGlueBalances(asset, collaterals, true);

// Supply delta (burn proportion)
uint256 supplyDelta = _md512(burnAmount, PRECISION, totalSupply);

// Is token trading below backing? (user can check off-chain, act on-chain)
// No oracle needed — arbitrage handles alignment
```

## Stage 2: Oracle Evaluation

### When Oracles Are Needed

- Real-world data: weather, sports scores, election results
- Cross-chain data: prices on other chains
- Real-time market prices: if can't use Glue ratios or TWAP
- Off-chain events: flight delays, package delivery, etc.

### Oracle Risks

| Risk | Description | Impact |
|------|------------|--------|
| **Trust** | Oracle operator can lie | Funds stolen/lost |
| **Manipulation** | Oracle data can be manipulated | Unfair outcomes |
| **Failure** | Oracle goes offline | Contract stuck |
| **Stale data** | Price not updated recently | Wrong calculations |
| **Gas cost** | Oracle calls cost extra gas | Higher tx fees |
| **Centralization** | Single oracle = single point of failure | Protocol dies with oracle |
| **Latency** | Data delayed vs real-time | Exploitable time windows |

### Minimum 5 Oracle Alternatives

Always propose these before using an oracle:

1. **Use Glue collateral ratios** — If the data is about token value, the Glue backing IS the on-chain price floor. No oracle needed.

2. **User-provided data + slippage protection** — User submits the data themselves with bounds. Contract validates within acceptable range. Example: "I believe price is $2000 ± 5%" → contract checks if that's reasonable vs last known state.

3. **Uniswap TWAP** — Time-weighted average price from on-chain DEX. ⚠️ Warning: manipulatable with large capital, especially on low-liquidity pairs. Better than single-block price but not bulletproof.

4. **Multiple oracle aggregation + median** — Use 3+ oracles (Chainlink, Pyth, Redstone), take the median. More expensive but resistant to single oracle failure/manipulation.

5. **Fallback to manual mode** — Use oracle when available, fall back to user-provided or admin-provided data with timelock if oracle fails. Never get stuck.

6. **Circuit breakers** — If oracle returns data outside reasonable bounds (>50% change in 1 hour), pause and require manual review.

7. **Time-weighted averages on-chain** — Track data points over time on-chain, use moving average. Slower to manipulate.

Let user decide the tradeoff — explain risks clearly.

## Stage 3: Off-Chain Evaluation

### When Off-Chain Is Needed

- Periodic automation (harvesting, rebalancing, liquidations)
- Complex computation too expensive for gas
- Privacy requirements (private inputs)
- Integration with Web2 services

### Off-Chain Risks

| Risk | Description | Impact |
|------|------------|--------|
| **Centralization** | Server operator has power | Single point of failure |
| **Downtime** | Server goes offline | Missed executions |
| **Frontrunning** | Keeper sees tx in mempool | Value extracted |
| **Ongoing cost** | Servers, infrastructure | Project dies if unfunded |
| **Trust** | Users must trust operator | Rug risk |
| **Censorship** | Operator can selectively execute | Unfair treatment |

### Minimum 5 Off-Chain Alternatives

1. **Anyone-can-call + incentive reward** — Make the function public. Pay a small reward (from Glue fees or reserves) to whoever calls it. Economic incentive = decentralized execution. Example: `function harvest() → caller gets 1% of harvest as reward`.

2. **User-initiated with better UX** — Instead of automation, give users a button. "Claim your rewards" instead of auto-distribute. Simpler, no keeper needed, user pays gas.

3. **Decentralized keeper network** — Gelato Network or Chainlink Automation. More decentralized than a single server, but still trust + cost.

4. **Fallback manual execution** — Primary: automated. Fallback: anyone can call after timeout. `if (block.timestamp > lastExecution + 1 days) → anyone can execute`.

5. **Event-driven from other contracts** — Hook into existing protocol actions. Example: "Rebalance on every swap" → use Uniswap hook or StickyAsset hook instead of keeper.

6. **Batch operations** — Instead of keeper running every block, batch updates. Process everything in one tx per day/week. Reduces keeper frequency and cost.

7. **Optimistic execution + dispute period** — Execute first, allow challenges within time window. If no dispute → finalized. Reduces on-chain computation.

## Common Patterns

### "I need real-time price feeds"

**Before using Chainlink:**
- Can you use Glue backing ratio as price floor? (0 oracle cost)
- Can you use Uniswap TWAP? (on-chain, ~3000 gas)
- Can users provide price with slippage bounds? (0 oracle cost)
- Do you ACTUALLY need real-time, or is hourly/daily enough?

### "I need automated harvesting"

**Before using a keeper:**
- Can users harvest themselves and get a reward?
- Can it happen on every unglue via hooks?
- Can you batch weekly instead of continuously?
- Can you use Gelato/Chainlink Automation as decentralized fallback?

### "I need random numbers"

**On-chain options:**
- Chainlink VRF (trusted, costs LINK)
- Commit-reveal (trustless, 2 transactions)
- Block hash (⚠️ manipulatable by miners/validators)
- Multiple party random generation

### "I need cross-chain data"

**Options:**
- Optimistic bridge (slow, cheap, trustless-ish)
- Trusted bridge (fast, centralized)
- LayerZero / Axelar / Wormhole (varying trust assumptions)
- Deploy on same chain to avoid cross-chain entirely

## If Truly Impossible On-Chain

When something genuinely cannot be done on-chain, explain:

1. **WHY** it's not possible (specific technical limitation)
2. **WHAT** off-chain infrastructure is needed (oracle, keeper, server)
3. **RISKS** of that infrastructure (trust, centralization, failure)
4. **MITIGATIONS** (fallbacks, circuit breakers, multi-oracle)
5. **ALTERNATIVES** that achieve similar result more on-chain

Examples:
- Real-time sports betting → ALT: User-provided results + dispute period + oracle backup
- AI-powered trading → ALT: User-defined strategies on-chain + off-chain signal generation
- Instant cross-chain → ALT: Optimistic bridge + dispute, or trusted bridge + explain tradeoffs
- Weather-based insurance → ALT: Multi-oracle with median + circuit breaker + admin fallback with timelock

**ALWAYS give the on-chain alternative, even if imperfect.** Let the user decide the tradeoff.
