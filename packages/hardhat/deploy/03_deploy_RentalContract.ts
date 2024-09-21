import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const deployRentalContract: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  // Get the deployed TravelToken
  const travelToken = await hre.deployments.get("TravelToken");

  if (!travelToken) {
    throw new Error("TravelToken not deployed");
  }

  console.log("TravelToken address:", travelToken.address);

  await deploy("RentalContract", {
    from: deployer,
    args: [travelToken.address], // Pass the TravelToken address here
    log: true,
    autoMine: true,
  });

  // const rentalContract = await hre.ethers.getContract("RentalContract", deployer);
};

export default deployRentalContract;

deployRentalContract.tags = ["RentalContract"];
deployRentalContract.dependencies = ["TravelToken"]; // This ensures TravelToken is deployed first
