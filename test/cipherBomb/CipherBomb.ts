import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstances } from "../instance";
import { Signers, getSigners } from "../signers";
import { createTransaction } from "../utils";
import { deployCipherBombFixture } from "./CipherBomb.fixture";

describe("CipherBomb", function () {
  before(async function () {
    this.signers = await getSigners(ethers);
  });

  beforeEach(async function () {
    const contract = await deployCipherBombFixture();
    this.contractAddress = await contract.getAddress();
    this.cipherbomb = contract;
    this.instances = await createInstances(this.contractAddress, ethers, this.signers);
  });

  it.only("should start a game", async function () {
    const openTx = await createTransaction(this.cipherbomb.open);
    await openTx.wait();

    expect(await this.cipherbomb.gameOpen()).to.be.true;
    expect(await this.cipherbomb.gameRunning()).to.be.false;

    const users: (keyof Signers)[] = ["bob", "carol", "dave"];
    const txs = users.map(async (user) => {
      const tx = await createTransaction(this.cipherbomb.connect(this.signers[user]).join);
      return tx.wait();
    });
    await Promise.all(txs);

    expect(await this.cipherbomb.numberOfPlayers()).to.eq(4);

    const startTx = await createTransaction(this.cipherbomb.start);
    await startTx.wait();

    expect(await this.cipherbomb.gameOpen()).to.be.false;
    expect(await this.cipherbomb.gameRunning()).to.be.true;
    expect(await this.cipherbomb.turnCurrentPlayer()).to.be.eq(this.signers.alice.address);

    const dealCards = async () => {
      const dealTx = await createTransaction(this.cipherbomb.deal);
      await dealTx.wait();

      const checkTx = await createTransaction(this.cipherbomb.checkDeal);
      await checkTx.wait();

      if (await this.cipherbomb.turnDealNeeded()) {
        await dealCards();
      }
    };
    await dealCards();

    const aliceCards = await this.cipherbomb.getMyCards(this.signers.alice);
    const aliceRole = await this.cipherbomb.getMyRole(this.signers.alice);
    console.log(`Alice (${aliceRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(aliceCards));

    const bobCards = await this.cipherbomb.getMyCards(this.signers.bob);
    const bobRole = await this.cipherbomb.getMyRole(this.signers.bob);
    console.log(`Bob (${bobRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(bobCards));

    const carolCards = await this.cipherbomb.getMyCards(this.signers.carol);
    const carolRole = await this.cipherbomb.getMyRole(this.signers.carol);
    console.log(`Carol (${carolRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(carolCards));

    const daveCards = await this.cipherbomb.getMyCards(this.signers.dave);
    const daveRole = await this.cipherbomb.getMyRole(this.signers.dave);
    console.log(`Dave (${daveRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(daveCards));

    const takeCardTx = await createTransaction(this.cipherbomb.takeCard, this.signers.bob);
    await takeCardTx.wait();

    const newBobCards = await this.cipherbomb.getMyCards(this.signers.bob);
    expect(newBobCards[0] + newBobCards[1] + newBobCards[2]).to.be.eq(4);

    const takeCard2Tx = await createTransaction(this.cipherbomb.connect(this.signers.bob).takeCard, this.signers.alice);
    await takeCard2Tx.wait();

    const newAliceCards = await this.cipherbomb.getMyCards(this.signers.alice);
    expect(newAliceCards[0] + newAliceCards[1] + newAliceCards[2]).to.be.eq(4);
  });
});

const displayCards = (cards: bigint[]) => {
  return `${cards[0]} wire(s), ${cards[1]} bomb, ${cards[2]} neutral(s)`;
};
