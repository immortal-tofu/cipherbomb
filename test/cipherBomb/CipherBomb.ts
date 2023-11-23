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
    console.log(this.contractAddress);
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

    const aliceToken = this.instances.alice.getTokenSignature(this.contractAddress)!;
    const encryptedAliceCards = await this.cipherbomb.getCards(aliceToken.publicKey, aliceToken.signature);
    const aliceCards = encryptedAliceCards.map((v) => this.instances.alice.decrypt(this.contractAddress, v));
    const encryptedAliceRole = await this.cipherbomb.getRole(aliceToken.publicKey, aliceToken.signature);
    const aliceRole = this.instances.alice.decrypt(this.contractAddress, encryptedAliceRole);
    console.log(`Alice (${aliceRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(aliceCards));

    const bobToken = this.instances.bob.getTokenSignature(this.contractAddress)!;
    const encryptedBobCards = await this.cipherbomb
      .connect(this.signers.bob)
      .getCards(bobToken.publicKey, bobToken.signature);
    const bobCards = encryptedBobCards.map((v) => this.instances.bob.decrypt(this.contractAddress, v));
    const encryptedBobRole = await this.cipherbomb
      .connect(this.signers.bob)
      .getRole(bobToken.publicKey, bobToken.signature);
    const bobRole = this.instances.bob.decrypt(this.contractAddress, encryptedBobRole);
    console.log(`Bob (${bobRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(bobCards));

    const carolToken = this.instances.carol.getTokenSignature(this.contractAddress)!;
    const encryptedCarolCards = await this.cipherbomb
      .connect(this.signers.carol)
      .getCards(carolToken.publicKey, carolToken.signature);
    const carolCards = encryptedCarolCards.map((v) => this.instances.carol.decrypt(this.contractAddress, v));
    const encryptedCarolRole = await this.cipherbomb
      .connect(this.signers.carol)
      .getRole(carolToken.publicKey, carolToken.signature);
    const carolRole = this.instances.carol.decrypt(this.contractAddress, encryptedCarolRole);
    console.log(`Carol (${carolRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(carolCards));

    const daveToken = this.instances.dave.getTokenSignature(this.contractAddress)!;
    const encryptedDaveCards = await this.cipherbomb
      .connect(this.signers.dave)
      .getCards(daveToken.publicKey, daveToken.signature);
    const daveCards = encryptedDaveCards.map((v) => this.instances.dave.decrypt(this.contractAddress, v));
    const encryptedDaveRole = await this.cipherbomb
      .connect(this.signers.dave)
      .getRole(daveToken.publicKey, daveToken.signature);
    const daveRole = this.instances.dave.decrypt(this.contractAddress, encryptedDaveRole);
    console.log(`Dave (${daveRole ? "Good guy" : "Bad guy"}) cards:`, displayCards(daveCards));

    const takeCardTx = await createTransaction(this.cipherbomb.takeCard, this.signers.bob);
    await takeCardTx.wait();

    const newEncryptedBobCards = await this.cipherbomb
      .connect(this.signers.bob)
      .getCards(bobToken.publicKey, bobToken.signature);
    const newBobCards = newEncryptedBobCards.map((v) => this.instances.bob.decrypt(this.contractAddress, v));
    expect(newBobCards[0] + newBobCards[1] + newBobCards[2]).to.be.eq(4);

    const takeCard2Tx = await createTransaction(this.cipherbomb.connect(this.signers.bob).takeCard, this.signers.alice);
    await takeCard2Tx.wait();

    const newEncryptedAliceCards = await this.cipherbomb.getCards(aliceToken.publicKey, aliceToken.signature);
    const newAliceCards = newEncryptedAliceCards.map((v) => this.instances.alice.decrypt(this.contractAddress, v));
    expect(newAliceCards[0] + newAliceCards[1] + newAliceCards[2]).to.be.eq(4);
  });
});

const displayCards = (cards: number[]) => {
  return `${cards[0]} wire(s), ${cards[1]} bomb, ${cards[2]} neutral(s)`;
};
