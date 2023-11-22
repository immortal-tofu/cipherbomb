// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.19;

import "fhevm/lib/TFHE.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract CipherBomb is Ownable {
    uint public constant MIN_PLAYERS = 4;
    uint public constant MAX_PLAYERS = 6;
    uint8 public constant TYPE_WIRE = 1;
    uint8 public constant TYPE_BOMB = 2;
    uint8 public constant TYPE_NEUTRAL = 3;

    bool public gameRunning;
    bool public gameOpen;
    bool public gameRoleDealNeeded;

    uint8 public numberOfPlayers;
    address[6] public players;

    uint8 public turnIndex;
    uint8 public turnMove;
    bool public turnDealNeeded;
    address public turnCurrentPlayer;

    uint8 public remainingWires;

    euint8[6] wirePositions;
    euint8 bombPosition;

    mapping(address => ebool) roles;
    mapping(address => Cards) cards;

    struct Cards {
        euint8 bomb;
        euint8 wires;
        euint8 neutrals;
    }

    event GameStart();
    event Turn(uint8 turnIndex);

    event BombFound();
    event WireFound();

    event GoodGuysWin();
    event BadGuysWin();

    event FalseDeal();

    constructor() {
        gameRunning = false;
        gameOpen = false;
    }

    function open() public {
        gameOpen = true;
        gameRunning = false;
        turnIndex = 0;
        turnMove = 0;
        turnDealNeeded = true;
        gameRoleDealNeeded = true;
        delete players;
        numberOfPlayers = 0;
        addPlayer(msg.sender);
    }

    function start() public onlyGameOpen {
        require(numberOfPlayers >= MIN_PLAYERS, "Not enough player to start");
        gameOpen = false;
        gameRunning = true;
        remainingWires = numberOfPlayers;
        turnCurrentPlayer = players[0];
        giveRoles();
    }

    function join() public onlyGameOpen {
        require(numberOfPlayers < MAX_PLAYERS, "The game has enough players (8)");
        addPlayer(msg.sender);
    }

    function addPlayer(address player) internal onlyNewPlayer(player) {
        players[numberOfPlayers] = msg.sender;
        numberOfPlayers++;
    }

    function dealCards(uint8 positionsToGenerate) internal returns (euint8[] memory) {
        euint8[] memory positions = new euint8[](positionsToGenerate);
        euint16 random16;
        euint8 random8;
        if (positionsToGenerate >= 3) {
            random16 = TFHE.randEuint16();
            if (positionsToGenerate >= 6) {
                random8 = TFHE.randEuint8();
            }
        } else {
            random8 = TFHE.randEuint8();
        }

        for (uint i; i < positionsToGenerate; i++) {
            euint8 randBits;
            if (positionsToGenerate >= 3) {
                if (i >= 6) {
                    uint8 shift8 = uint8(3 * (i - 5));
                    randBits = TFHE.shr(random8, shift8);
                } else {
                    uint16 shift16 = uint16(3 * (i + 1));
                    randBits = TFHE.asEuint8(TFHE.shr(random16, shift16));
                }
            } else {
                uint8 shift8 = uint8(3 * (i + 1));
                randBits = TFHE.shr(random8, shift8);
            }
            uint8 mask = 7;
            euint8 player = TFHE.and(randBits, TFHE.asEuint8(mask));
            euint8 correctedPlayer = TFHE.cmux(
                TFHE.lt(player, numberOfPlayers),
                player,
                TFHE.sub(player, numberOfPlayers)
            );
            positions[i] = correctedPlayer;
        }

        return positions;
    }

    function deal() public onlyGameRunning onlyTurnDealNeeded {
        require(turnDealNeeded, "There is no need to deal cards");
        euint8[] memory positions = dealCards(uint8(remainingWires + 1));
        for (uint i; i < positions.length; i++) {
            if (i == positions.length - 1) {
                bombPosition = positions[i];
            } else {
                wirePositions[i] = positions[i];
            }
        }
    }

    function turnCardLimit() internal view returns (uint8) {
        return uint8(5 - turnIndex);
    }

    function checkDeal() public onlyGameRunning onlyTurnDealNeeded {
        ebool dealIsCorrect = TFHE.asEbool(true);
        for (uint8 i; i < numberOfPlayers; i++) {
            euint8 wires = TFHE.asEuint8(0);
            for (uint8 j; j < remainingWires; j++) {
                wires = wires + TFHE.asEuint8(TFHE.eq(wirePositions[j], i));
            }
            euint8 bomb = TFHE.asEuint8(TFHE.eq(bombPosition, i));
            euint8 neutrals = TFHE.asEuint8(turnCardLimit()) - (wires + bomb);
            cards[players[i]] = Cards(bomb, wires, neutrals);
            dealIsCorrect = TFHE.and(dealIsCorrect, TFHE.le(wires + bomb, turnCardLimit()));
        }
        turnDealNeeded = !TFHE.decrypt(dealIsCorrect);
        if (turnDealNeeded) {
            emit FalseDeal();
        }
    }

    function giveRoles() internal onlyRoleDealNeeded {
        uint8 badGuys = 2;
        euint8[] memory positions = dealCards(badGuys);
        if (numberOfPlayers > 4) {
            bool equal = TFHE.decrypt(TFHE.eq(positions[0], positions[1]));
            if (equal) {
                giveRoles();
                return;
            }
        }
        for (uint8 i; i < numberOfPlayers; i++) {
            ebool role = TFHE.asEbool(true); // Nice guy
            for (uint8 j; j < 2; j++) {
                role = TFHE.and(role, TFHE.ne(positions[j], i));
            }
            roles[players[i]] = role;
        }
        gameRoleDealNeeded = false;
    }

    function getMyRole(address player) public view onlyGameRunning onlyPlayer(player) returns (bool) {
        bool role = TFHE.decrypt(roles[player]);
        return role;
    }

    function getMyCards(address player) public view onlyGameRunning onlyPlayer(player) returns (uint[3] memory) {
        uint wires = TFHE.decrypt(cards[player].wires);
        uint bomb = TFHE.decrypt(cards[player].bomb);
        uint neutrals = TFHE.decrypt(cards[player].neutrals);
        return [wires, bomb, neutrals];
    }

    function endGame() internal {
        gameRunning = false;
        gameOpen = false;
    }

    function takeCard(address player) public onlyGameRunning onlyTurnRunning onlyCurrentPlayer(msg.sender) {
        euint8 totalCards = cards[player].wires + cards[player].bomb + cards[player].neutrals;
        euint8 cardToTake = TFHE.shr(TFHE.randEuint8(), 5); // 3 bits of randomness
        euint8 correctedCard = TFHE.cmux(TFHE.lt(cardToTake, totalCards), cardToTake, cardToTake - totalCards);
        ebool cardIsWire = TFHE.and(TFHE.gt(cards[player].wires, 0), TFHE.lt(correctedCard, cards[player].wires));
        ebool cardIsBomb = TFHE.and(TFHE.eq(cards[player].bomb, 1), TFHE.eq(correctedCard, cards[player].wires));

        cards[player].wires = TFHE.cmux(cardIsWire, TFHE.sub(cards[player].wires, 1), cards[player].wires);
        cards[player].bomb = TFHE.cmux(cardIsBomb, TFHE.sub(cards[player].bomb, 1), cards[player].bomb);
        cards[player].neutrals = TFHE.cmux(
            TFHE.or(cardIsBomb, cardIsWire),
            cards[player].neutrals,
            TFHE.sub(cards[player].neutrals, 1)
        );

        euint8 eCardType = TFHE.asEuint8(TYPE_NEUTRAL);
        eCardType = TFHE.cmux(cardIsWire, TFHE.asEuint8(TYPE_WIRE), eCardType);
        eCardType = TFHE.cmux(cardIsBomb, TFHE.asEuint8(TYPE_BOMB), eCardType);

        turnMove++;

        uint cardType = TFHE.decrypt(eCardType);
        if (cardType == TYPE_BOMB) {
            emit BombFound();
            emit BadGuysWin();
            endGame();
            return;
        }

        if (cardType == TYPE_WIRE) {
            emit WireFound();
            remainingWires--;
            if (remainingWires == 0) {
                emit GoodGuysWin();
                endGame();
                return;
            }
        }

        if (turnMove == numberOfPlayers) {
            turnIndex++;
            if (turnIndex == 4) {
                emit BadGuysWin();
                endGame();
                return;
            }
            turnMove = 0;
            turnDealNeeded = true;
        }

        turnCurrentPlayer = player;
    }

    modifier onlyPlayer(address player) {
        bool exists = false;
        for (uint8 i; i < numberOfPlayers; i++) {
            if (players[i] == player) exists = true;
        }
        require(exists, "This player doesn't exist");
        _;
    }

    modifier onlyNewPlayer(address player) {
        bool newPlayer = true;
        for (uint8 i; i < numberOfPlayers; i++) {
            if (players[i] == player) newPlayer = false;
        }
        require(newPlayer);
        _;
    }

    modifier onlyGameRunning() {
        require(!gameOpen && gameRunning, "The game is not running");
        _;
    }

    modifier onlyGameOpen() {
        require(gameOpen && !gameRunning, "The game is not open");
        _;
    }

    modifier onlyRoleDealNeeded() {
        require(gameRoleDealNeeded, "No need to deal cards");
        _;
    }

    modifier onlyTurnRunning() {
        require(turnMove < numberOfPlayers && !turnDealNeeded, "Need to deal cards");
        _;
    }

    modifier onlyTurnDealNeeded() {
        require(turnDealNeeded, "No need to deal cards");
        _;
    }

    modifier onlyCurrentPlayer(address player) {
        require(turnCurrentPlayer == player, "It's not your turn!");
        _;
    }
}
