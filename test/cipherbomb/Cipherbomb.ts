import { expect } from "chai";

import { awaitAllDecryptionResults } from "../asyncDecrypt";
import { createInstances } from "../instance";
import { getSigners, initSigners } from "../signers";
import { FhevmInstances } from "../types";
import { deployCipherbombFixture } from "./Cipherbomb.fixture";

describe("Cipherbomb", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployCipherbombFixture();
    this.contractAddress = await contract.getAddress();
    this.cipherbomb = contract;
    this.instances = await createInstances(this.signers);
  });

  it("should create a game", async function () {
    const transaction = await this.cipherbomb.createGame();
    await transaction.wait();

    const game = await this.cipherbomb.games(0);
    console.log(game);
    expect(game[0]).to.equal(this.signers.alice.address);
    expect(game[1]).to.equal(false);
    expect(game[2]).to.equal(true);
    expect(game[3]).to.equal(true);
    expect(game[4]).to.equal(0n);
    expect(game[5]).to.equal(0n);
    expect(game[6]).to.equal(0n);
    expect(game[7]).to.equal(this.signers.alice.address);
    expect(game[8]).to.equal(0n);
    expect(game[9]).to.equal(0n);
    expect(game[10]).to.equal(0n);
    expect(game[11]).to.equal(0n);
    expect(game[12]).to.equal(0n);

    const players = await this.cipherbomb.getPlayers(0);
    expect(players.length).to.equal(1);
    expect(players[0]).to.equal(this.signers.alice.address);
  });

  it("should join a game", async function () {
    const transaction = await this.cipherbomb.createGame();
    await transaction.wait();

    const join = await this.cipherbomb.connect(this.signers.bob).join(0);
    await join.wait();

    const players = await this.cipherbomb.getPlayers(0);
    expect(players.length).to.equal(2);
    expect(players[1]).to.equal(this.signers.bob.address);
  });

  it("should kick a player", async function () {
    const transaction = await this.cipherbomb.createGame();
    await transaction.wait();

    const join = await this.cipherbomb.connect(this.signers.bob).join(0);
    await join.wait();

    const kick = await this.cipherbomb.kick(0, this.signers.bob);
    await kick.wait();

    const players = await this.cipherbomb.getPlayers(0);
    expect(players.length).to.equal(1);
    expect(players[0]).to.equal(this.signers.alice.address);
  });

  it("should leave the game", async function () {
    const transaction = await this.cipherbomb.createGame();
    await transaction.wait();

    const join = await this.cipherbomb.connect(this.signers.bob).join(0);
    await join.wait();
    const join2 = await this.cipherbomb.connect(this.signers.carol).join(0);
    await join2.wait();
    const join3 = await this.cipherbomb.connect(this.signers.dave).join(0);
    await join3.wait();

    const players = await this.cipherbomb.getPlayers(0);
    expect(players.length).to.equal(4);

    const leave = await this.cipherbomb.connect(this.signers.bob).leave(0);
    await leave.wait();

    const players1 = await this.cipherbomb.getPlayers(0);
    expect(players1.length).to.equal(3);
    expect(players1[0]).to.equal(this.signers.alice.address);
    expect(players1[2]).to.equal(this.signers.dave.address);

    const leave2 = await this.cipherbomb.connect(this.signers.dave).leave(0);
    await leave2.wait();

    const players2 = await this.cipherbomb.getPlayers(0);
    expect(players2.length).to.equal(2);
    expect(players2[0]).to.equal(this.signers.alice.address);
    expect(players2[1]).to.equal(this.signers.carol.address);
  });

  it("should start a game", async function () {
    const transaction = await this.cipherbomb.createGame();
    await transaction.wait();

    const join = await this.cipherbomb.connect(this.signers.bob).join(0);
    await join.wait();
    const join2 = await this.cipherbomb.connect(this.signers.carol).join(0);
    await join2.wait();
    const join3 = await this.cipherbomb.connect(this.signers.dave).join(0);
    await join3.wait();

    const start = await this.cipherbomb.start(0);
    await start.wait();
    await awaitAllDecryptionResults();

    const reencrypt = async (user: keyof FhevmInstances, handle: bigint) => {
      const { publicKey, privateKey } = this.instances[user].generateKeypair();
      const eip712 = this.instances[user].createEIP712(publicKey, this.contractAddress);
      const signature = await this.signers[user].signTypedData(
        eip712.domain,
        { Reencrypt: eip712.types.Reencrypt },
        eip712.message,
      );
      return await this.instances[user].reencrypt(
        handle,
        privateKey,
        publicKey,
        signature.replace("0x", ""),
        this.contractAddress,
        this.signers[user].address,
      );
    };

    await (await this.cipherbomb.takeRole(0, 0)).wait();
    await (await this.cipherbomb.takeRole(0, 1)).wait();
    await (await this.cipherbomb.takeRole(0, 2)).wait();
    await (await this.cipherbomb.takeRole(0, 3)).wait();

    const encryptedRoleAlice = await this.cipherbomb.getRole(0, 0);
    const aliceRole = await reencrypt("alice", encryptedRoleAlice);
    console.log("alice", aliceRole ? "bad guy" : "good guy", aliceRole.toString(2));

    const encryptedRoleBob = await this.cipherbomb.getRole(0, 1);
    const bobRole = await reencrypt("bob", encryptedRoleBob);
    console.log("bob", bobRole ? "bad guy" : "good guy", bobRole.toString(2));

    const encryptedRoleCarol = await this.cipherbomb.getRole(0, 2);
    const carolRole = await reencrypt("carol", encryptedRoleCarol);
    console.log("carol", carolRole ? "bad guy" : "good guy", carolRole.toString(2));

    const encryptedRoleDave = await this.cipherbomb.getRole(0, 3);
    const daveRole = await reencrypt("dave", encryptedRoleDave);
    console.log("dave", daveRole ? "bad guy" : "good guy", daveRole.toString(2));
  });

  it.only("should deal cards", async function () {
    const transaction = await this.cipherbomb.createGame();
    await transaction.wait();

    const join = await this.cipherbomb.connect(this.signers.bob).join(0);
    await join.wait();
    const join2 = await this.cipherbomb.connect(this.signers.carol).join(0);
    await join2.wait();
    const join3 = await this.cipherbomb.connect(this.signers.dave).join(0);
    await join3.wait();

    const start = await this.cipherbomb.start(0);
    await start.wait();
    await awaitAllDecryptionResults();

    const reencrypt = async (user: keyof FhevmInstances, handle: bigint) => {
      const { publicKey, privateKey } = this.instances[user].generateKeypair();
      const eip712 = this.instances[user].createEIP712(publicKey, this.contractAddress);
      const signature = await this.signers[user].signTypedData(
        eip712.domain,
        { Reencrypt: eip712.types.Reencrypt },
        eip712.message,
      );
      console.log("start reencrypt");
      return await this.instances[user].reencrypt(
        handle,
        privateKey,
        publicKey,
        signature.replace("0x", ""),
        this.contractAddress,
        this.signers[user].address,
      );
    };

    const deal = await this.cipherbomb.deal(0);
    await deal.wait();
    await awaitAllDecryptionResults();
    console.log("dealed");
    const txCards = [
      await this.cipherbomb.takeCards(0, 0),
      await this.cipherbomb.takeCards(0, 1),
      await this.cipherbomb.takeCards(0, 2),
      await this.cipherbomb.takeCards(0, 3),
    ];
    await Promise.all(txCards.map((tx) => tx.wait()));

    const encryptedCardsAlice = await this.cipherbomb.getCards(0, 0);
    const aliceCards = await reencrypt("alice", encryptedCardsAlice);
    console.log("alice", aliceCards, aliceCards.toString(2));

    const encryptedCardsBob = await this.cipherbomb.getCards(0, 1);
    const bobCards = await reencrypt("bob", encryptedCardsBob);
    console.log("bob", bobCards, bobCards.toString(2));

    const encryptedCardsCarol = await this.cipherbomb.getCards(0, 2);
    const carolCards = await reencrypt("carol", encryptedCardsCarol);
    console.log("carol", carolCards, carolCards.toString(2));

    const encryptedCardsDave = await this.cipherbomb.getCards(0, 3);
    const daveCards = await reencrypt("dave", encryptedCardsDave);
    console.log("dave", daveCards, daveCards.toString(2));
  });
});
