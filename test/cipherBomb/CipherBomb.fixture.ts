import { ethers } from 'hardhat';

import type { CipherBomb } from '../../types';
import { getSigners } from '../signers';

export async function deployCipherBombFixture(): Promise<CipherBomb> {
  const signers = await getSigners(ethers);

  const contractFactory = await ethers.getContractFactory('CipherBomb');
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();

  return contract;
}
