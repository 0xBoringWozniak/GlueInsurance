# Security Checklist

## Pre-Code Analysis (Reality Check)

Before writing ANY code, analyze the idea critically:

### 1. Is It Actually Achievable On-Chain?

Not every idea works on-chain. Check:
- Does it need real-time external data? (needs oracle = risk)
- Does it need automation? (needs keeper = risk)
- Does it need privacy? (everything on-chain is public)
- Does it need computation that's too expensive for gas?

If yes to any → run 3-Stage Feasibility Check (see SKILL.md).

### 2. Does the Logic Work as a Closed System?

- Can money enter AND leave?
- Does total value in = total value out (accounting for fees)?
- Are there states where funds get permanently locked?
- What happens at edge cases? (0 users, 1 user, max users, 0 balance, max balance)

### 3. Who Controls What?

Map every function to its caller:
- `onlyOwner` functions → What can the owner do? Can they rug?
- `public/external` functions → Can anyone call? Is that safe?
- No access control → Is it intentionally permissionless?

**Red flags:**
- Owner can withdraw all funds
- Owner can change critical parameters without timelock
- Owner can pause withdrawals indefinitely
- Single EOA controls everything (no multisig)

### 4. Obvious Attack Vectors

Check for these BEFORE coding:

| Attack | Pattern | Example |
|--------|---------|---------|
| **Anyone-can-decide** | Unprotected function determines outcomes | `closeBet(winner)` callable by anyone → caller sets themselves as winner |
| **Admin rug** | Owner has too much power | `withdrawAll()` drains user funds |
| **Frontrunning** | Transaction can be sandwiched | User submits trade → MEV bot sees mempool → extracts value |
| **Flash loan manipulation** | Temporary state change exploitable | Borrow → inflate price → profit → repay |
| **Griefing** | Attacker wastes others' gas/funds | Spamming small deposits to block withdrawals |

### 5. Economic Viability

- Do ALL participants have economic incentive?
- Is risk/reward balanced?
- Would rational actors use this? (If only losing money → bad design)

---

## 7-Point Code Checklist

Run this on EVERY contract before providing to user. Fix ALL issues first.

### ✅ 1. Access Control

**Check:** Are `onlyOwner`, `onlyRole`, or custom modifiers applied correctly?

```solidity
// ❌ BAD — anyone can close a bet and set winner
function closeBet(uint256 betId, address winner) external {
    bets[betId].winner = winner;
    bets[betId].closed = true;
}

// ✅ GOOD — only oracle can determine winner
function closeBet(uint256 betId, address winner) external onlyOracle {
    require(!bets[betId].closed, "Already closed");
    require(winner != address(0), "Invalid winner");
    bets[betId].winner = winner;
    bets[betId].closed = true;
    emit BetClosed(betId, winner);
}
```

**Verify:**
- Admin functions have proper modifiers
- Critical state changes are protected
- Public functions are intentionally public and safe to call by anyone
- Consider if owner powers are too broad (can owner rug users?)

### ✅ 2. No Obvious Exploits

**Check:** Can anyone drain funds, manipulate results, or steal value?

```solidity
// ❌ BAD — anyone can claim any amount
function claim(uint256 amount) external {
    _transferAsset(token, msg.sender, amount, new uint256[](0), true);
}

// ✅ GOOD — tracked balances, claim only what's owed
function claim() external {
    uint256 owed = balances[msg.sender];
    require(owed > 0, "Nothing to claim");
    balances[msg.sender] = 0; // Effects before interactions
    _transferAsset(token, msg.sender, owed, new uint256[](0), true);
}
```

**Verify:**
- No unprotected withdrawal functions
- No ways to manipulate results/outcomes
- No ways to extract more value than deposited
- Flash loan attack resistance considered

### ✅ 3. Reentrancy Protection

**Check:** All state-changing external functions use `nnrtnt` modifier.

```solidity
// ❌ BAD — no reentrancy protection
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount);
    _transferAsset(address(0), msg.sender, amount, new uint256[](0), true);
    balances[msg.sender] -= amount;
    // ^ Attacker re-enters before balance update!
}

// ✅ GOOD — nnrtnt + checks-effects-interactions
function withdraw(uint256 amount) external nnrtnt {
    require(balances[msg.sender] >= amount, "Insufficient");
    balances[msg.sender] -= amount; // Effects BEFORE interactions
    _transferAsset(address(0), msg.sender, amount, new uint256[](0), true);
    emit Withdrawn(msg.sender, amount);
}
```

**Verify:**
- Every external/public state-changing function has `nnrtnt`
- State updates happen BEFORE external calls (checks-effects-interactions pattern)
- Even with `nnrtnt`, follow CEI as defense-in-depth

### ✅ 4. Math Safety

**Check:** All multiplication/division uses `_md512`, no raw operators.

```solidity
// ❌ BAD — potential overflow, precision loss
uint256 fee = amount * feeRate / PRECISION;
uint256 share = balance * userAmount / totalAmount;

// ✅ GOOD — 512-bit safe
uint256 fee = _md512(amount, feeRate, PRECISION);
uint256 share = _md512(balance, userAmount, totalAmount);

// ✅ GOOD — rounded up for fees (prevents zero-fee on small amounts)
uint256 fee = _md512Up(amount, feeRate, PRECISION);
```

**Verify:**
- No `*` followed by `/` in the same expression
- All percentage calculations use `_md512` with `PRECISION`
- Fee calculations use `_md512Up` (round up to protect protocol)
- No division by zero possible (check denominators)
- No underflow (check subtraction order)

### ✅ 5. Input Validation

**Check:** Zero checks, array limits, address validation.

```solidity
// ❌ BAD — no validation
function deposit(address token, uint256 amount) external {
    _transferFromAsset(token, msg.sender, address(this), amount, new uint256[](0), true);
}

// ✅ GOOD — complete validation
function deposit(address token, uint256 amount) external nnrtnt {
    require(token != address(0), "Invalid token");
    require(amount > 0, "Zero amount");
    require(allowedTokens[token], "Token not supported");
    uint256 actual = _transferFromAsset(
        token, msg.sender, address(this), amount, new uint256[](0), true
    );
    balances[msg.sender][token] += actual; // Use actual, not amount (tax tokens)
    emit Deposited(msg.sender, token, actual);
}
```

**Verify:**
- `require(amount > 0)` on all amount parameters
- `require(address != address(0))` where relevant
- Array length limits: `require(arr.length <= 100, "Too many")`
- No duplicate entries in arrays if that would cause issues
- Enum/status checks for state machines

### ✅ 6. Fund Accounting

**Check:** Can't withdraw more than deposited, balances always track correctly.

```solidity
// ❌ BAD — no balance tracking, anyone can drain
function withdraw(address token, uint256 amount) external {
    _transferAsset(token, msg.sender, amount, new uint256[](0), true);
}

// ✅ GOOD — tracked, verified, effects-before-interactions
function withdraw(address token, uint256 amount) external nnrtnt {
    require(balances[msg.sender][token] >= amount, "Insufficient");
    balances[msg.sender][token] -= amount;
    _transferAsset(token, msg.sender, amount, new uint256[](0), true);
    emit Withdrawn(msg.sender, token, amount);
}
```

**Verify:**
- Every deposit increases a tracked balance
- Every withdrawal decreases a tracked balance first (CEI)
- `balances[user] -= amount` before `_transferAsset`
- Tax token amounts: use `actual` received, not `amount` requested
- Total contract balance >= sum of all user balances
- No way to create balance from nothing

### ✅ 7. Logic Integrity

**Check:** Closed system, incentives aligned, no circular dependencies.

```solidity
// ❌ BAD — circular: contract depends on its own token price
function rebase() external {
    uint256 price = getPrice(); // Gets own token price from DEX
    uint256 newSupply = _md512(totalSupply, price, targetPrice);
    // Price changes → supply changes → price changes → ∞
}

// ✅ GOOD — uses external reference, bounded
function rebase() external nnrtnt {
    uint256 ethBacking = _getGlueBalances(token, collaterals, true)[0];
    uint256 targetBacking = _md512(totalSupply(), targetPerToken, PRECISION);
    require(ethBacking > targetBacking, "Below target");
    // Logic based on actual collateral, not circular price
}
```

**Verify:**
- No circular dependencies (A depends on B depends on A)
- State machine transitions are valid (can't skip states)
- Time-dependent logic uses `block.timestamp` correctly
- Events emitted for all significant state changes
- No dead code paths where funds get stuck

---

## Loop Optimization

Unbounded loops = gas risk + DoS attack vector. **ALWAYS warn users.**

```solidity
// ❌ BAD — unbounded, attacker adds 10,000 entries → function unusable
for (uint256 i; i < users.length; i++) {
    _transferAsset(token, users[i], amounts[i], new uint256[](0), true);
}

// ✅ GOOD — bounded with limit
require(users.length <= 100, "Too many recipients");
for (uint256 i; i < users.length; i++) {
    _transferAsset(token, users[i], amounts[i], new uint256[](0), true);
}
```

**Best practices:**
- Set explicit limits: `require(arr.length <= 100)`
- Use batch functions: `_batchTransferAsset` (from GluedTools)
- Implement pagination for large datasets
- Consider gas costs per iteration (~21,000 gas per external call)
- If users can grow an array → it's an attack vector

---

## Quick Security Audit Flow

1. **Read the whole contract** — understand what it does
2. **Map access control** — who can call what?
3. **Trace fund flows** — money in, money out, where does it go?
4. **Check every external call** — reentrancy protected?
5. **Check every calculation** — using `_md512`?
6. **Check every input** — validated?
7. **Check edge cases** — 0 amount? empty array? last user? first user?
8. **Economic analysis** — would a rational attacker profit?

If ANY issue found → fix it, explain to user what was wrong and why.
