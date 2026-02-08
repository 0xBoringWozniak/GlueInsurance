import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const asset = await MockUSDC.deploy();
  await asset.waitForDeployment();

  const InsurancePool = await ethers.getContractFactory("InsurancePool");
  const pool = await InsurancePool.deploy(await asset.getAddress(), deployer.address);
  await pool.waitForDeployment();

  const InsuranceGlueVault = await ethers.getContractFactory("InsuranceGlueVault");
  const vault = await InsuranceGlueVault.deploy(
    await asset.getAddress(),
    "Insurance Glue Vault",
    "iGLUE",
    deployer.address,
    deployer.address,
    deployer.address,
    await pool.getAddress()
  );
  await vault.waitForDeployment();

  await (await pool.setVault(await vault.getAddress())).wait();

  console.log("MockUSDC:", await asset.getAddress());
  console.log("InsurancePool:", await pool.getAddress());
  console.log("InsuranceGlueVault:", await vault.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
