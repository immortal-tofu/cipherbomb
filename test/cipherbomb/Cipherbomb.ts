import { expect } from "chai";

import { createInstances } from "../instance";
import { getSigners, initSigners } from "../signers";
import { deployCipherbombFixture } from "./Cipherbomb.fixture";

describe("EncryptedERC20", function () {
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
    expect(game[0]).to.equal(this.signers.alice.address);
    console.log(game);
  });
});
