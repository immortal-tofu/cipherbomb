import { ethers } from "hardhat";

import type { Cipherbomb } from "../../types";
import { getSigners } from "../signers";

export async function deployCipherbombFixture(): Promise<Cipherbomb> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("Cipherbomb");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();

  return contract;
}
