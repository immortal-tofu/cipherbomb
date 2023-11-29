import { expect } from 'chai';
import { ethers } from 'hardhat';

import { createInstances } from '../instance';
import { Signers, getSigners } from '../signers';
import { createTransaction } from '../utils';
import { deployCipherBombFixture } from './CipherBomb.fixture';

describe('CipherBomb', function () {
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

  it('should start a game', async function () {
    const getCard = async (name: string) => {
      const key = name as keyof Signers;
      const token = this.instances[key].getTokenSignature(this.contractAddress)!;
      const encryptedCards = await this.cipherbomb
        .connect(this.signers[key])
        .getMyCards(token.publicKey, token.signature);
      const cards = encryptedCards.map((v) => this.instances[key].decrypt(this.contractAddress, v));
      const encryptedRole = await this.cipherbomb.connect(this.signers[key]).getRole(token.publicKey, token.signature);
      const role = this.instances[key].decrypt(this.contractAddress, encryptedRole);
      return { cards, role };
    };

    const getPlayers = async () => {
      const players: { name: string; wires: number }[] = [];
      const p = ['alice', 'bob', 'carol', 'dave'].map(async (name) => {
        const { cards, role } = await getCard(name as keyof Signers);
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

    const takeCards = async (firstPlayer: string, players: { name: string; wires: number }[], move: number) => {
      let currentPlayer = firstPlayer;
      let nextPlayer = players[0].name !== currentPlayer ? players[0].name : players[1].name;
      for (let i = 0; i < move; i += 1) {
        console.log(`${currentPlayer} takes a card from ${nextPlayer}`);
        const takeCardTx = await createTransaction(
          this.cipherbomb.connect(this.signers[currentPlayer as keyof Signers]).takeCard,
          this.signers[nextPlayer as keyof Signers],
        );
        await takeCardTx.wait();
        currentPlayer = nextPlayer;
        nextPlayer = players[0].name !== currentPlayer ? players[0].name : players[1].name;
      }
      return currentPlayer;
    };

    expect(await this.cipherbomb.gameOpen()).to.be.true;
    expect(await this.cipherbomb.gameRunning()).to.be.false;

    const users: (keyof Signers)[] = ['bob', 'carol', 'dave'];
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
      // Add delay to avoid stuck transaction after
      await new Promise((resolve) => setTimeout(resolve, 2000));
    };
    console.log('TURN 1: 5 cards');

    await dealCards();

    const cards = await this.cipherbomb.getCards();
    expect(cards[0]).to.be.eq(5n);
    expect(cards[1]).to.be.eq(5n);
    expect(cards[2]).to.be.eq(5n);
    expect(cards[3]).to.be.eq(5n);
    console.log(cards);

    // TURN 1: 5 cards

    const players = await getPlayers();

    const turn2Player = await takeCards('alice', players, 4);

    const newAliceCards = await getCard(turn2Player as keyof Signers);
    expect(newAliceCards.cards[0] + newAliceCards.cards[1] + newAliceCards.cards[2]).to.be.eq(3);

    // TURN 2: 4 cards
    console.log('TURN 2: 4 cards');

    await dealCards();

    const turn2Players = await getPlayers();

    const turnCards = await getCard('alice');
    expect(turnCards.cards[0] + turnCards.cards[1] + turnCards.cards[2]).to.be.eq(4);

    const turn3Player = await takeCards(turn2Player, turn2Players, 4);

    const turn2Cards = await getCard(turn3Player);
    expect(turn2Cards.cards[0] + turn2Cards.cards[1] + turn2Cards.cards[2]).to.be.eq(2);

    // TURN 3: 3 cards
    console.log('TURN 3: 3 cards');

    await dealCards();

    const turn3Players = await getPlayers();

    const turn4Player = await takeCards(turn3Player, turn3Players, 4);

    const turn3Cards = await getCard(turn4Player);
    expect(turn3Cards.cards[0] + turn3Cards.cards[1] + turn3Cards.cards[2]).to.be.eq(1);

    // TURN 4: 2 cards
    console.log('TURN 4: 2 cards');

    await dealCards();

    const turn4Players = await getPlayers();
    const badGuysWin = new Promise((resolve) => {
      void this.cipherbomb.on(this.cipherbomb.filters.BadGuysWin, () => {
        resolve(true);
      });
    });
    await takeCards(turn4Player, turn4Players, 4);
    await badGuysWin;
  });
});

const displayCards = (cards: number[]) => {
  return `${cards[0]} wire(s), ${cards[1]} bomb, ${cards[2]} neutral(s)`;
};
