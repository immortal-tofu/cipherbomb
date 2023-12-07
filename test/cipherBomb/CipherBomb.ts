import { expect } from 'chai';
import { ethers } from 'hardhat';

import { CipherBomb } from '../../types';
import { createInstances } from '../instance';
import { Signers, getSigners } from '../signers';
import { FhevmInstances } from '../types';
import { createTransaction } from '../utils';
import { deployCipherBombFixture } from './CipherBomb.fixture';

describe('CipherBomb', function () {
  before(async function () {
    this.signers = await getSigners(ethers);
    // console.log(this.signers.alice.address);
    // console.log(this.signers.bob.address);
    // console.log(this.signers.carol.address);
    // console.log(this.signers.dave.address);
    // console.log(this.signers.eve.address);
    // console.log(this.signers.oscar.address);
  });

  beforeEach(async function () {
    const contract = await deployCipherBombFixture();
    this.contractAddress = await contract.getAddress();
    console.log(this.contractAddress);
    this.cipherbomb = contract;
    this.instances = await createInstances(this.contractAddress, ethers, this.signers);
  });

  const start = async (contract: CipherBomb) => {
    const startTx = await createTransaction(contract.start);
    await startTx.wait();
    if (await contract.gameRoleDealNeeded()) {
      await start(contract);
    }
  };

  const getRole = async (contract: CipherBomb, instances: FhevmInstances, signers: Signers, name: string) => {
    const key = name as keyof FhevmInstances;
    const contractAddress = await contract.getAddress();
    const token = instances[key].getTokenSignature(contractAddress)!;
    const encryptedRole = await contract.connect(signers[key]).getRole(token.publicKey, token.signature);
    return instances[key].decrypt(contractAddress, encryptedRole);
  };

  const getCard = async (contract: CipherBomb, instances: FhevmInstances, signers: Signers, name: string) => {
    const key = name as keyof FhevmInstances;
    const contractAddress = await contract.getAddress();
    const token = instances[key].getTokenSignature(contractAddress)!;
    const encryptedCards = await contract.connect(signers[key]).getMyCards(token.publicKey, token.signature);
    const cards = encryptedCards.map((v) => instances[key].decrypt(contractAddress, v));
    return cards;
  };

  const getPlayers = async (contract: CipherBomb, instances: FhevmInstances, signers: Signers, users: string[]) => {
    const players: { name: string; wires: number }[] = [];
    const p = users.map(async (name) => {
      const cards = await getCard(contract, instances, signers, name);
      const role = await getRole(contract, instances, signers, name);
      console.log(`${name} (${role ? 'Good guy' : 'Bad guy'}) cards:`, displayCards(cards));

      if (cards[1]) return;
      players.push({ name, wires: cards[0] });
    });
    await Promise.all(p);
    players.sort((a, b) => {
      if (a.wires < b.wires) {
        return -1;
      } else if (a.wires > b.wires) {
        return 1;
      }
      // a must be equal to b
      return 0;
    });
    console.log(players);
    return players;
  };

  const takeCards = async (
    contract: CipherBomb,
    signers: Signers,
    firstPlayer: string,
    players: { name: string; wires: number }[],
    move: number,
  ) => {
    let currentPlayer = firstPlayer;
    let nextPlayer = players[0].name !== currentPlayer ? players[0].name : players[1].name;
    await new Array(move).fill(null).reduce(async (p) => {
      await p;
      console.log(`${currentPlayer} takes a card from ${nextPlayer}`);
      const takeCardTx = await createTransaction(
        contract.connect(signers[currentPlayer as keyof Signers]).takeCard,
        signers[nextPlayer as keyof Signers],
      );
      await takeCardTx.wait();
      currentPlayer = nextPlayer;
      nextPlayer = players[0].name !== currentPlayer ? players[0].name : players[1].name;
    }, Promise.resolve());

    return currentPlayer;
  };

  const dealCards = async (contract: CipherBomb) => {
    const dealTx = await createTransaction(contract.deal);
    await dealTx.wait();
    console.log('deal done');
    const checkTx = await createTransaction(contract.checkDeal);
    await checkTx.wait();
    console.log('deal checked');
    if (await contract.turnDealNeeded()) {
      await dealCards(contract);
    }
    // Add delay to avoid stuck transaction after
    await new Promise((resolve) => setTimeout(resolve, 7500));
  };

  const join = async (contract: CipherBomb, signers: Signers, users: (keyof Signers)[]) => {
    const txs = users.map(async (user) => {
      if (user === 'alice') return;
      const tx = await createTransaction(contract.connect(signers[user]).join);
      return tx.wait();
    });
    await Promise.all(txs);
  };

  it('should start a game with 4 players', async function () {
    const users: (keyof Signers)[] = ['alice', 'bob', 'carol', 'dave'];

    expect(await this.cipherbomb.gameOpen()).to.be.true;
    expect(await this.cipherbomb.gameRunning()).to.be.false;

    await join(this.cipherbomb, this.signers, users);

    expect(await this.cipherbomb.numberOfPlayers()).to.eq(4);

    await start(this.cipherbomb);

    expect(await this.cipherbomb.gameOpen()).to.be.false;
    expect(await this.cipherbomb.gameRunning()).to.be.true;
    expect(await this.cipherbomb.turnCurrentPlayer()).to.be.eq(this.signers.alice.address);

    console.log('TURN 1: 5 cards');

    await dealCards(this.cipherbomb);

    const cards = await this.cipherbomb.getCards();
    expect(cards[0]).to.be.eq(5n);
    expect(cards[1]).to.be.eq(5n);
    expect(cards[2]).to.be.eq(5n);
    expect(cards[3]).to.be.eq(5n);
    console.log(cards);

    // TURN 1: 5 cards

    const players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);

    const turn2Player = await takeCards(this.cipherbomb, this.signers, 'alice', players, users.length);

    const newAliceCards = await getCard(this.cipherbomb, this.instances, this.signers, turn2Player as keyof Signers);
    expect(newAliceCards[0] + newAliceCards[1] + newAliceCards[2]).to.be.eq(3);

    // TURN 2: 4 cards
    console.log('TURN 2: 4 cards');

    await dealCards(this.cipherbomb);

    const turn2Players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);

    const turnCards = await getCard(this.cipherbomb, this.instances, this.signers, 'alice');
    expect(turnCards[0] + turnCards[1] + turnCards[2]).to.be.eq(4);

    const turn3Player = await takeCards(this.cipherbomb, this.signers, turn2Player, turn2Players, users.length);

    const turn2Cards = await getCard(this.cipherbomb, this.instances, this.signers, turn3Player);
    expect(turn2Cards[0] + turn2Cards[1] + turn2Cards[2]).to.be.eq(2);

    // TURN 3: 3 cards
    console.log('TURN 3: 3 cards');

    await dealCards(this.cipherbomb);

    const turn3Players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);

    const turn4Player = await takeCards(this.cipherbomb, this.signers, turn3Player, turn3Players, users.length);

    const turn3Cards = await getCard(this.cipherbomb, this.instances, this.signers, turn4Player);
    expect(turn3Cards[0] + turn3Cards[1] + turn3Cards[2]).to.be.eq(1);

    // TURN 4: 2 cards
    console.log('TURN 4: 2 cards');

    await dealCards(this.cipherbomb);

    const turn4Players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);
    const badGuysWin = new Promise((resolve) => {
      void this.cipherbomb.on(this.cipherbomb.filters.BadGuysWin, () => {
        resolve(true);
      });
    });
    await takeCards(this.cipherbomb, this.signers, turn4Player, turn4Players, users.length);
    await badGuysWin;
  });

  it('should start a game with 6 players', async function () {
    const users: (keyof Signers)[] = ['alice', 'bob', 'carol', 'dave', 'eve', 'oscar'];

    expect(await this.cipherbomb.gameOpen()).to.be.true;
    expect(await this.cipherbomb.gameRunning()).to.be.false;

    await join(this.cipherbomb, this.signers, users);

    expect(await this.cipherbomb.numberOfPlayers()).to.eq(6);

    await start(this.cipherbomb);

    expect(await this.cipherbomb.gameOpen()).to.be.false;
    expect(await this.cipherbomb.gameRunning()).to.be.true;
    expect(await this.cipherbomb.turnCurrentPlayer()).to.be.eq(this.signers.alice.address);

    console.log('TURN 1: 5 cards');

    await dealCards(this.cipherbomb);

    const cards = await this.cipherbomb.getCards();
    expect(cards[0]).to.be.eq(5n);
    expect(cards[1]).to.be.eq(5n);
    expect(cards[2]).to.be.eq(5n);
    expect(cards[3]).to.be.eq(5n);
    expect(cards[4]).to.be.eq(5n);
    expect(cards[5]).to.be.eq(5n);
    console.log(cards);

    // TURN 1: 5 cards

    const players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);

    const turn2Player = await takeCards(this.cipherbomb, this.signers, 'alice', players, users.length);

    const newAliceCards = await getCard(this.cipherbomb, this.instances, this.signers, turn2Player as keyof Signers);
    expect(newAliceCards[0] + newAliceCards[1] + newAliceCards[2]).to.be.eq(2);

    // TURN 2: 4 cards
    console.log('TURN 2: 4 cards');

    await dealCards(this.cipherbomb);

    const turn2Players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);

    const turnCards = await getCard(this.cipherbomb, this.instances, this.signers, 'alice');
    expect(turnCards[0] + turnCards[1] + turnCards[2]).to.be.eq(4);

    const turn3Player = await takeCards(this.cipherbomb, this.signers, turn2Player, turn2Players, users.length);

    const turn2Cards = await getCard(this.cipherbomb, this.instances, this.signers, turn3Player);
    expect(turn2Cards[0] + turn2Cards[1] + turn2Cards[2]).to.be.eq(1);

    // TURN 3: 3 cards
    console.log('TURN 3: 3 cards');

    await dealCards(this.cipherbomb);

    const turn3Players = await getPlayers(this.cipherbomb, this.instances, this.signers, users);

    const turn4Player = await takeCards(this.cipherbomb, this.signers, turn3Player, turn3Players, users.length);

    const turn3Cards = await getCard(this.cipherbomb, this.instances, this.signers, turn4Player);
    expect(turn3Cards[0] + turn3Cards[1] + turn3Cards[2]).to.be.eq(0);

    // TURN 4: 2 cards
    console.log('TURN 4: 2 cards');

    await dealCards(this.cipherbomb);
  });
});

const displayCards = (cards: number[]) => {
  return `${cards[0]} wire(s), ${cards[1]} bomb, ${cards[2]} neutral(s)`;
};
