# Contract Templates

Ready-to-use Solidity patterns for common Glue integrations. Copy, customize, deploy.

## Template 1: Basic Sticky Token (ERC20)

The simplest Glue-backed token. No hooks, no custom logic.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@glue-finance/expansions-pack/contracts/StickyAsset.sol";

contract MyToken is ERC20, StickyAsset {
    constructor()
        ERC20("My Token", "MTK")
        StickyAsset(
            "ipfs://metadata-uri",  // Contract metadata URI
            [true, false]            // [fungible=true, hasHook=false]
        )
    {
        _mint(msg.sender, 1_000_000 * 1e18); // 1M tokens to deployer
    }
}
```

**What happens on deploy:**
1. Mints 1M tokens to deployer
2. Auto-creates a Glue contract for this token via GlueStick factory
3. Anyone can send ETH/ERC20 to the Glue to add backing
4. Holders can call `unglue()` to burn tokens for proportional collateral

## Template 2: Revenue-Sharing Token (Collateral Hook)

Takes a percentage of collateral during unglue and routes it to a treasury.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@glue-finance/expansions-pack/contracts/StickyAsset.sol";

contract RevenueToken is ERC20, StickyAsset {
    address public immutable treasury;
    uint256 public constant HOOK_FEE = 1e17; // 10% of collateral to treasury

    constructor(address _treasury)
        ERC20("Revenue Token", "RVT")
        StickyAsset(
            "ipfs://metadata-uri",
            [true, true]  // [fungible=true, hasHook=TRUE]
        )
    {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
        _mint(msg.sender, 1_000_000 * 1e18);
    }

    /// @notice How much collateral the hook takes (10%)
    function _calculateCollateralHookSize(
        address,        // asset (unused — same % for all collaterals)
        uint256 amount  // collateral amount after protocol fee
    ) internal pure override returns (uint256) {
        return _md512(amount, HOOK_FEE, PRECISION);
    }

    /// @notice Routes the hook's share to treasury
    function _processCollateralHook(
        address asset,
        uint256 hookAmount,
        bool isETH,
        address          // recipient (unused)
    ) internal override {
        if (isETH) {
            // ETH: send directly
            payable(treasury).transfer(hookAmount);
        } else {
            // ERC20: use safe transfer
            _transferAsset(asset, treasury, hookAmount, new uint256[](0), true);
        }
    }
}
```

**Economics:**
- User burns 10,000 tokens from 1M supply with 100 ETH backing
- Base share: 1% of 100 ETH = 1 ETH
- Protocol fee: 0.1% = 0.001 ETH
- After protocol fee: 0.999 ETH
- Hook (10%): 0.0999 ETH → treasury
- User receives: 0.8991 ETH

## Template 3: Sticky Hook (Token-Side Deduction)

Takes a percentage of tokens being burned and routes them somewhere (e.g., lock, redistribution).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@glue-finance/expansions-pack/contracts/StickyAsset.sol";

contract StickyHookToken is ERC20, StickyAsset {
    address public immutable lockVault;
    uint256 public constant STICKY_FEE = 5e16; // 5% of tokens locked

    constructor(address _lockVault)
        ERC20("Sticky Hook Token", "SHT")
        StickyAsset("ipfs://metadata-uri", [true, true])
    {
        require(_lockVault != address(0), "Invalid vault");
        lockVault = _lockVault;
        _mint(msg.sender, 1_000_000 * 1e18);
    }

    /// @notice How many tokens the sticky hook takes (5%)
    function _calculateStickyHookSize(uint256 amount) 
        internal pure override returns (uint256) 
    {
        return _md512(amount, STICKY_FEE, PRECISION);
    }

    /// @notice Routes the hook's token share to lock vault
    function _processStickyHook(
        uint256 hookAmount,
        uint256[] memory,  // tokenIds (unused for ERC20)
        address             // recipient (unused)
    ) internal override {
        _transferAsset(address(this), lockVault, hookAmount, new uint256[](0), true);
    }
}
```

**Economics:**
- User tries to burn 10,000 tokens
- Sticky hook takes 5% = 500 tokens → sent to lock vault
- Effective burn = 9,500 tokens
- Supply delta calculated on 9,500, not 10,000
- Result: slightly less collateral per burn, but tokens accumulate in vault

## Template 4: Flash Loan Strategy (GluedLoanReceiver)

Borrow from Glue collateral, do something profitable, repay + fee.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@glue-finance/expansions-pack/contracts/GluedLoanReceiver.sol";

contract ArbitrageBot is GluedLoanReceiver {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Your strategy logic — called after receiving the loan
    function _executeFlashLoanLogic(bytes memory params) 
        internal override returns (bool) 
    {
        // At this point, borrowed funds are in this contract
        uint256 borrowed = getCurrentTotalBorrowed();
        address collateral = getCurrentCollateral();
        uint256 fees = getCurrentTotalFees();
        
        // Decode your custom parameters
        // (address targetDex, uint256 minProfit) = abi.decode(params, (address, uint256));

        // === YOUR ARBITRAGE LOGIC HERE ===
        // Example: buy cheap token on DEX A, sell expensive on DEX B
        // Must end with enough to repay borrowed + fees

        // Repayment happens automatically after this returns true
        return true;
    }

    /// @notice Trigger a single-Glue flash loan
    function executeArbitrage(
        address glue,
        address collateral,
        uint256 amount,
        bytes calldata params
    ) external onlyOwner nnrtnt {
        _requestFlashLoan(glue, collateral, amount, params);
    }

    /// @notice Trigger a multi-Glue flash loan (aggregate liquidity)
    function executeMultiArbitrage(
        address[] calldata glues,
        address collateral,
        uint256 amount,
        bytes calldata params
    ) external onlyOwner nnrtnt {
        _requestGluedLoan(false, glues, collateral, amount, params);
    }

    /// @notice Withdraw profits
    function withdraw(address token, uint256 amount) external onlyOwner {
        _transferAsset(token, owner, amount, new uint256[](0), true);
    }

    /// @notice Accept ETH
    receive() external payable {}
}
```

**Flash Loan Economics:**
- Borrow 10 ETH from Glue
- Fee: 10 × 0.01% = 0.001 ETH
- Must repay: 10.001 ETH in same transaction
- If arbitrage profit > 0.001 ETH + gas → profitable

## Template 5: Router / Integration Contract (GluedToolsERC20)

A contract that interacts with existing Glues (not creating new tokens).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@glue-finance/expansions-pack/contracts/GluedToolsERC20.sol";

contract GlueRouter is GluedToolsERC20 {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Initialize a Glue for any ERC20 token
    function createGlue(address token) external returns (address glue) {
        glue = _initializeGlue(token, true);
    }

    /// @notice Check if a token has a Glue
    function checkGlue(address token) external view returns (bool hasGlue, address glue) {
        (glue, hasGlue) = _getGlue(token, true);
    }

    /// @notice Deposit tokens into their Glue (creates Glue if needed)
    function depositToGlue(address token, uint256 amount) external nnrtnt {
        require(amount > 0, "Zero amount");
        
        // Get or create Glue
        address glue = _initializeGlue(token, true);
        
        // Transfer tokens from user to Glue
        uint256 actual = _transferFromAsset(
            token, msg.sender, glue, amount, new uint256[](0), true
        );
        
        emit Deposited(msg.sender, token, actual, glue);
    }

    /// @notice Get backing info for a token
    function getBackingInfo(
        address token, 
        address[] calldata collaterals
    ) external view returns (uint256[] memory balances, uint256 supply) {
        balances = _getGlueBalances(token, collaterals, true);
        supply = _getTotalSupply(token, true);
    }

    /// @notice Batch transfer tokens to multiple recipients
    function distribute(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256 total
    ) external nnrtnt {
        require(recipients.length <= 100, "Too many recipients");
        require(recipients.length == amounts.length, "Length mismatch");
        
        _transferFromAsset(token, msg.sender, address(this), total, new uint256[](0), true);
        _batchTransferAsset(token, recipients, amounts, new uint256[](0), total, true);
    }

    event Deposited(address indexed user, address indexed token, uint256 amount, address glue);

    receive() external payable {}
}
```

## Template 6: Test Template

```typescript
// test/MyToken.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { MyToken } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("MyToken", () => {
  let token: MyToken;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async () => {
    [owner, user1, user2] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("MyToken");
    token = await Factory.deploy();
    await token.waitForDeployment();
  });

  describe("Deployment", () => {
    it("should mint total supply to deployer", async () => {
      const balance = await token.balanceOf(owner.address);
      expect(balance).to.equal(ethers.parseEther("1000000"));
    });

    it("should have a Glue address", async () => {
      const glue = await token.GLUE();
      expect(glue).to.not.equal(ethers.ZeroAddress);
    });
  });

  describe("Backing", () => {
    it("should accept ETH as collateral", async () => {
      const glue = await token.GLUE();
      
      // Send 1 ETH to Glue
      await owner.sendTransaction({
        to: glue,
        value: ethers.parseEther("1"),
      });

      const balance = await ethers.provider.getBalance(glue);
      expect(balance).to.equal(ethers.parseEther("1"));
    });
  });

  describe("Unglue", () => {
    beforeEach(async () => {
      // Setup: send 10 ETH to Glue as backing
      const glue = await token.GLUE();
      await owner.sendTransaction({
        to: glue,
        value: ethers.parseEther("10"),
      });

      // Transfer some tokens to user1
      await token.transfer(user1.address, ethers.parseEther("10000"));
    });

    it("should allow burning tokens for collateral", async () => {
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      
      // Unglue 10,000 tokens (1% of 1M supply)
      await token.connect(user1).unglue(
        [ethers.ZeroAddress],                // ETH collateral
        ethers.parseEther("10000"),          // amount
        [],                                   // empty tokenIds (ERC20)
        user1.address                         // recipient
      );

      const balanceAfter = await ethers.provider.getBalance(user1.address);
      // Should receive ~0.0999 ETH (1% of 10 ETH minus 0.1% fee, minus gas)
      expect(balanceAfter).to.be.greaterThan(balanceBefore);
    });

    it("should reduce total supply after burn", async () => {
      const supplyBefore = await token.totalSupply();
      
      await token.connect(user1).unglue(
        [ethers.ZeroAddress],
        ethers.parseEther("10000"),
        [],
        user1.address
      );

      const supplyAfter = await token.totalSupply();
      expect(supplyAfter).to.be.lessThan(supplyBefore);
    });
  });
});
```

## Template 7: Deploy Script

```typescript
// scripts/deploy.ts
import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", ethers.formatEther(
    await ethers.provider.getBalance(deployer.address)
  ), "ETH");

  // Deploy token
  const TokenFactory = await ethers.getContractFactory("MyToken");
  const token = await TokenFactory.deploy();
  await token.waitForDeployment();

  const tokenAddress = await token.getAddress();
  const glueAddress = await token.GLUE();

  console.log("=".repeat(50));
  console.log("Token deployed to:", tokenAddress);
  console.log("Glue address:", glueAddress);
  console.log("=".repeat(50));
  console.log("");
  console.log("Verify with:");
  console.log(`npx hardhat verify --network ${process.env.HARDHAT_NETWORK || 'sepolia'} ${tokenAddress}`);
  console.log("");
  console.log("Send collateral to Glue:", glueAddress);
  console.log("View on Etherscan:", `https://etherscan.io/address/${tokenAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

## Template 8: Deploy Script with Constructor Args

For contracts that take constructor arguments (e.g., RevenueToken):

```typescript
// scripts/deploy-revenue.ts
import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const treasuryAddress = "0xYourTreasuryAddress"; // Set your treasury

  const TokenFactory = await ethers.getContractFactory("RevenueToken");
  const token = await TokenFactory.deploy(treasuryAddress);
  await token.waitForDeployment();

  const tokenAddress = await token.getAddress();
  const glueAddress = await token.GLUE();

  console.log("Token:", tokenAddress);
  console.log("Glue:", glueAddress);
  console.log("Treasury:", treasuryAddress);
  console.log("");
  console.log("Verify:");
  console.log(`npx hardhat verify --network sepolia ${tokenAddress} ${treasuryAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

## Which Template Do I Need?

| Use Case | Template |
|----------|----------|
| Simple backed token | Template 1 (Basic Sticky Token) |
| Token with treasury fee on unglue | Template 2 (Revenue — Collateral Hook) |
| Token that locks portion on burn | Template 3 (Sticky Hook) |
| Arbitrage / liquidation bot | Template 4 (Flash Loan) |
| App interacting with existing Glues | Template 5 (Router) |
| Tests for any of the above | Template 6 (Test) |
| Deploy any contract | Template 7 or 8 (Deploy) |
