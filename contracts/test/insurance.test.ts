import { expect } from "chai";
import { ethers } from "hardhat";

describe("Insurance module", function () {
  async function deployFixture() {
    const [owner, insurer1, insurer2, caller] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const usdc = await MockUSDC.deploy();
    await usdc.waitForDeployment();

    const MockGlueStick = await ethers.getContractFactory("MockGlueStick");
    const mockGlueStick = await MockGlueStick.deploy();
    await mockGlueStick.waitForDeployment();

    const MockERC4626Vault = await ethers.getContractFactory("MockERC4626Vault");
    const vault = await MockERC4626Vault.deploy(await usdc.getAddress());
    await vault.waitForDeployment();

    const InsurancePool = await ethers.getContractFactory("InsurancePool");
    const pool = await InsurancePool.deploy(
      await usdc.getAddress(),
      ethers.parseEther("0.10"),
      1_000_000n * 10n ** 6n,
      3600,
      10,
      owner.address
    );
    await pool.waitForDeployment();

    const INSToken = await ethers.getContractFactory("INSToken");
    const ins = await INSToken.deploy("Insurance Share", "INS", owner.address, await mockGlueStick.getAddress());
    await ins.waitForDeployment();

    await pool.connect(owner).setVault(await vault.getAddress());
    await pool.connect(owner).setINSToken(await ins.getAddress());
    await ins.connect(owner).setPool(await pool.getAddress());

    const InsuranceRegistry = await ethers.getContractFactory("InsuranceRegistry");
    const registry = await InsuranceRegistry.deploy();
    await registry.waitForDeployment();
    await registry.registerVault(await vault.getAddress(), await pool.getAddress());

    await usdc.mint(insurer1.address, 10_000_000n * 10n ** 6n);
    await usdc.mint(insurer2.address, 10_000_000n * 10n ** 6n);
    await usdc.mint(await vault.getAddress(), 10_000_000n * 10n ** 6n);

    await vault.setTotalSupply(1_000_000n * 10n ** 18n);
    await vault.setTotalAssets(1_000_000n * 10n ** 6n);

    await usdc.connect(insurer1).approve(await pool.getAddress(), ethers.MaxUint256);
    await usdc.connect(insurer2).approve(await pool.getAddress(), ethers.MaxUint256);

    return { owner, insurer1, insurer2, caller, usdc, vault, pool, ins, registry };
  }

  it("1) INS minting first deposit", async function () {
    const { insurer1, pool, ins } = await deployFixture();

    await pool.connect(insurer1).deposit(1_000n * 10n ** 6n, insurer1.address);

    expect(await ins.balanceOf(insurer1.address)).to.equal(1_000n * 10n ** 6n);
  });

  it("2) proportional minting", async function () {
    const { insurer1, insurer2, pool, ins } = await deployFixture();

    await pool.connect(insurer1).deposit(1_000n * 10n ** 6n, insurer1.address);
    await pool.connect(insurer2).deposit(500n * 10n ** 6n, insurer2.address);

    expect(await ins.balanceOf(insurer2.address)).to.equal(500n * 10n ** 6n);
  });

  it("3) withdraw logic", async function () {
    const { insurer1, usdc, pool, ins } = await deployFixture();

    await pool.connect(insurer1).deposit(1_000n * 10n ** 6n, insurer1.address);
    await pool.connect(insurer1).withdraw(400n * 10n ** 6n, insurer1.address);

    expect(await ins.balanceOf(insurer1.address)).to.equal(600n * 10n ** 6n);
    expect(await usdc.balanceOf(insurer1.address)).to.equal(9_999_400n * 10n ** 6n);
  });

  it("4) premium increases INS Glue collateral without mint", async function () {
    const { insurer1, usdc, vault, pool, ins } = await deployFixture();

    await pool.connect(insurer1).deposit(1_000n * 10n ** 6n, insurer1.address);
    const supplyBefore = await ins.totalSupply();
    const poolAssetsBefore = await pool.poolAssets();

    await vault.payPremiumToPool(await pool.getAddress(), 300n * 10n ** 6n);

    expect(await pool.poolAssets()).to.equal(poolAssetsBefore);
    expect(await pool.insGlueCollateral()).to.equal(300n * 10n ** 6n);
    expect(await usdc.balanceOf(await ins.glue())).to.equal(300n * 10n ** 6n);
    expect(await ins.totalSupply()).to.equal(supplyBefore);
  });

  it("5) checkpoint update rules", async function () {
    const { vault, pool } = await deployFixture();

    await pool.updateCheckpoint();
    const first = await pool.checkpointPPS();

    await expect(pool.updateCheckpoint()).to.be.reverted;

    await ethers.provider.send("evm_increaseTime", [24 * 60 * 60 + 1]);
    await ethers.provider.send("evm_mine", []);

    await vault.setTotalAssets(1_100_000n * 10n ** 6n);
    await pool.updateCheckpoint();

    expect(await pool.checkpointPPS()).to.be.gt(first);

    await ethers.provider.send("evm_increaseTime", [24 * 60 * 60 + 1]);
    await ethers.provider.send("evm_mine", []);

    await vault.setTotalAssets(1_050_000n * 10n ** 6n);
    await expect(pool.updateCheckpoint()).to.be.reverted;
  });

  it("6) triggerLoss payout correctness", async function () {
    const { insurer1, vault, pool, usdc } = await deployFixture();

    await pool.connect(insurer1).deposit(2_000n * 10n ** 6n, insurer1.address);
    await pool.updateCheckpoint();

    await vault.setTotalAssets(850_000n * 10n ** 6n);
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    const vaultBalBefore = await usdc.balanceOf(await vault.getAddress());
    const tx = await pool.triggerLoss();
    await tx.wait();

    const vaultBalAfter = await usdc.balanceOf(await vault.getAddress());
    expect(vaultBalAfter - vaultBalBefore).to.equal(1_998_000_000n);
  });

  it("7) deductible enforcement", async function () {
    const { insurer1, vault, pool } = await deployFixture();

    await pool.connect(insurer1).deposit(5_000n * 10n ** 6n, insurer1.address);
    await pool.updateCheckpoint();

    await vault.setTotalAssets(950_000n * 10n ** 6n);
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await expect(pool.triggerLoss()).to.be.reverted;
  });

  it("8) caller reward paid", async function () {
    const { insurer1, caller, vault, pool, usdc } = await deployFixture();

    await pool.connect(insurer1).deposit(3_000n * 10n ** 6n, insurer1.address);
    await pool.updateCheckpoint();

    await vault.setTotalAssets(800_000n * 10n ** 6n);
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    const before = await usdc.balanceOf(caller.address);
    await pool.connect(caller).triggerLoss();
    const after = await usdc.balanceOf(caller.address);

    expect(after - before).to.equal(3_000_000n);
  });

  it("9) cooldown enforced", async function () {
    const { insurer1, caller, vault, pool } = await deployFixture();

    await pool.connect(insurer1).deposit(10_000n * 10n ** 6n, insurer1.address);
    await pool.updateCheckpoint();

    await vault.setTotalAssets(800_000n * 10n ** 6n);
    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    await pool.connect(caller).triggerLoss();
    await expect(pool.connect(caller).triggerLoss()).to.be.reverted;
  });

  it("10) insufficient liquidity protection", async function () {
    const { insurer1, caller, vault, pool, usdc } = await deployFixture();

    await pool.connect(insurer1).deposit(500n * 10n ** 6n, insurer1.address);
    await pool.connect(insurer1).withdraw(500n * 10n ** 6n, insurer1.address);

    await pool.connect(insurer1).deposit(100n * 10n ** 6n, insurer1.address);
    await pool.setParameters(ethers.parseEther("0.10"), 0, 3600, 10);

    await pool.updateCheckpoint();
    await vault.setTotalAssets(700_000n * 10n ** 6n);

    await ethers.provider.send("evm_increaseTime", [3601]);
    await ethers.provider.send("evm_mine", []);

    const callerBalBefore = await usdc.balanceOf(caller.address);
    await expect(pool.connect(caller).triggerLoss()).to.be.reverted;
    expect(await usdc.balanceOf(caller.address)).to.equal(callerBalBefore);
  });
});
