import { expect } from "chai";
import { ethers } from "hardhat";

describe("InsuranceGlueVault", function () {
  async function fixture() {
    const [owner, alice, insurer, treasury] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    const asset = await MockUSDC.deploy();
    await asset.waitForDeployment();

    const InsurancePool = await ethers.getContractFactory("InsurancePool");
    const pool = await InsurancePool.deploy(await asset.getAddress(), owner.address);
    await pool.waitForDeployment();

    const InsuranceGlueVault = await ethers.getContractFactory("InsuranceGlueVault");
    const vault = await InsuranceGlueVault.deploy(
      await asset.getAddress(),
      "Insurance Glue Vault",
      "iGLUE",
      owner.address,
      treasury.address,
      owner.address,
      await pool.getAddress()
    );
    await vault.waitForDeployment();

    await pool.setVault(await vault.getAddress());

    const oneMillion = 1_000_000n * 10n ** 6n;
    const twoHundredThousand = 200_000n * 10n ** 6n;

    await asset.mint(alice.address, oneMillion);
    await asset.mint(insurer.address, twoHundredThousand);
    await asset.mint(owner.address, twoHundredThousand);

    await asset.connect(alice).approve(await vault.getAddress(), oneMillion);
    await asset.connect(insurer).approve(await pool.getAddress(), twoHundredThousand);
    await asset.connect(owner).approve(await vault.getAddress(), twoHundredThousand);

    return { owner, alice, insurer, treasury, asset, pool, vault };
  }

  it("routes management fees to insurance pool and treasury", async function () {
    const { alice, insurer, treasury, asset, pool, vault } = await fixture();

    await vault.connect(alice).deposit(1_000_000n * 10n ** 6n, alice.address);
    await pool.connect(insurer).stake(100_000n * 10n ** 6n);

    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    await vault.accrueFees();

    expect(await asset.balanceOf(treasury.address)).to.equal(10_000n * 10n ** 6n);
    expect(await pool.pendingPremium(insurer.address)).to.equal(10_000n * 10n ** 6n);

    await pool.connect(insurer).claim();
    expect(await asset.balanceOf(insurer.address)).to.equal(110_000n * 10n ** 6n);
  });

  it("charges performance fee on reported gains", async function () {
    const { owner, alice, insurer, treasury, asset, pool, vault } = await fixture();

    await vault.connect(alice).deposit(1_000_000n * 10n ** 6n, alice.address);
    await pool.connect(insurer).stake(100_000n * 10n ** 6n);

    await vault.connect(owner).report(100_000n * 10n ** 6n, 0);

    expect(await asset.balanceOf(treasury.address)).to.equal(10_000n * 10n ** 6n);
    expect(await pool.pendingPremium(insurer.address)).to.equal(10_000n * 10n ** 6n);
  });

  it("lets LP withdraw after fee accrual", async function () {
    const { alice, asset, vault } = await fixture();

    const initialDeposit = 1_000_000n * 10n ** 6n;
    await vault.connect(alice).deposit(initialDeposit, alice.address);

    await ethers.provider.send("evm_increaseTime", [180 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    await vault.accrueFees();

    const shares = await vault.balanceOf(alice.address);
    await vault.connect(alice).redeem(shares, alice.address, alice.address);

    const balanceAfter = await asset.balanceOf(alice.address);
    expect(balanceAfter).to.be.lessThan(initialDeposit);
    expect(balanceAfter).to.be.greaterThan(980_000n * 10n ** 6n);
  });
});
