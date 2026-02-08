import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const usdc = await MockUSDC.deploy();
  await usdc.waitForDeployment();

  const MockGlueStick = await ethers.getContractFactory("MockGlueStick");
  const glueStick = await MockGlueStick.deploy();
  await glueStick.waitForDeployment();

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
    deployer.address
  );
  await pool.waitForDeployment();

  const INSToken = await ethers.getContractFactory("INSToken");
  const ins = await INSToken.deploy("Insurance Share", "INS", 6, deployer.address, await glueStick.getAddress());
  await ins.waitForDeployment();

  const InsuranceRegistry = await ethers.getContractFactory("InsuranceRegistry");
  const registry = await InsuranceRegistry.deploy();
  await registry.waitForDeployment();

  await (await pool.setVault(await vault.getAddress())).wait();
  await (await pool.setINSToken(await ins.getAddress())).wait();
  await (await ins.setPool(await pool.getAddress())).wait();
  await (await registry.registerVault(await vault.getAddress(), await pool.getAddress())).wait();

  console.log("MockUSDC:", await usdc.getAddress());
  console.log("MockGlueStick:", await glueStick.getAddress());
  console.log("MockVault:", await vault.getAddress());
  console.log("InsurancePool:", await pool.getAddress());
  console.log("INSToken:", await ins.getAddress());
  console.log("INS Glue:", await ins.glue());
  console.log("Registry:", await registry.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
