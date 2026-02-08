import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const MockUSDC = await ethers.getContractFactory("MockUSDC");
  const asset = await MockUSDC.deploy();
  await asset.waitForDeployment();

  const MockGlueStick = await ethers.getContractFactory("MockGlueStick");
  const mockGlueStick = await MockGlueStick.deploy();
  await mockGlueStick.waitForDeployment();

  const InsuranceGlueVault = await ethers.getContractFactory("InsuranceGlueVault");
  const vault = await InsuranceGlueVault.deploy(
    await asset.getAddress(),
    "Glue Insurance Vault",
    "gINS",
    deployer.address,
    deployer.address,
    deployer.address,
    await mockGlueStick.getAddress()
  );
  await vault.waitForDeployment();

  console.log("MockUSDC:", await asset.getAddress());
  console.log("MockGlueStick:", await mockGlueStick.getAddress());
  console.log("InsuranceGlueVault:", await vault.getAddress());
  console.log("Glue:", await vault.glue());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
