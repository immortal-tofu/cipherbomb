import type { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';

export interface Signers {
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  dave: SignerWithAddress;
  eve: SignerWithAddress;
  oscar: SignerWithAddress;
}

export const getSigners = async (ethers: any): Promise<Signers> => {
  const signers = await ethers.getSigners();
  return {
    alice: signers[0],
    bob: signers[1],
    carol: signers[2],
    dave: signers[3],
    eve: signers[4],
    oscar: signers[5],
  };
};
