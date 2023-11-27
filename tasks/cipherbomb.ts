import { task } from "hardhat/config";
import type { TaskArguments } from "hardhat/types";

import { Signers, getSigners } from "../test/signers";

task("task:join")
  .addParam("address", "Address of the game")
  .addParam("account", "Specify which account [alice, bob, carol, dave]")
  .setAction(async function (taskArguments: TaskArguments, hre) {
    const { ethers } = hre;
    const signers = await getSigners(ethers);
    const cipherbomb = await ethers.getContractAt(
      "CipherBomb",
      taskArguments.address,
      signers[taskArguments.account as keyof Signers],
    );

    await cipherbomb.join();
    await cipherbomb.setName(taskArguments.account);

    console.log(`${taskArguments.account} joined!`);
  });

task("task:allJoin")
  .addParam("address", "Address of the game")
  .setAction(async function (taskArguments: TaskArguments, hre) {
    const { ethers } = hre;
    const signers = await getSigners(ethers);

    await ["alice", "bob", "carol"].reduce(async (previous, account) => {
      await previous;
      const cipherbomb = await ethers.getContractAt(
        "CipherBomb",
        taskArguments.address,
        signers[account as keyof Signers],
      );
      try {
        const tx = await cipherbomb.join();
        await cipherbomb.setName(account);
        await tx.wait();
      } catch (e) {
        console.error(e);
      }
      console.log(`${account} joined!`);
    }, Promise.resolve());
  });

task("task:takeCard")
  .addParam("address", "Address of the game")
  .addParam("account", "Specify which account [alice, bob, carol, dave]")
  .addParam("from", "Specify which account from take a card")
  .setAction(async function (taskArguments: TaskArguments, hre) {
    const { ethers } = hre;
    const signers = await getSigners(ethers);
    const cipherbomb = await ethers.getContractAt(
      "CipherBomb",
      taskArguments.address,
      signers[taskArguments.account as keyof Signers],
    );

    const tx = await cipherbomb.connect(signers[taskArguments.account as keyof Signers]).takeCard(taskArguments.from);
    await tx.wait();

    console.log(`${taskArguments.account} took a card from ${taskArguments.from}!`);
  });
