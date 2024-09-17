// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "./Dealer.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Cipherbomb is Dealer, GatewayCaller, Ownable2Step {
    uint256 public constant MIN_PLAYERS = 4;
    uint256 public constant MAX_PLAYERS = 8;

    enum CardType {
        WIRE,
        BOMB,
        NEUTRAL
    }

    struct Game {
        address admin;
        bool running;
        bool open;
        bool dealNeeded;
        address[] players;
        ebool[8] roles;
        uint8 roleMask;
        euint4[8] nullCards;
        euint4[8] wireCards;
        euint4[8] bombCard;
        uint8[8] remainingCards;
        uint64 cardsMask;
        uint8 turn;
        address turnCurrentPlayer;
        uint8 move;
        uint8 remainingWires;
        euint8 bombPosition;
        euint64 roleRandomness;
        euint64 cardsRandomness;
    }

    Game[] public games;

    mapping(address => string) nicknames;

    event PlayerJoined(uint256 gameId, address player);
    event PlayerLeft(uint256 gameId, address player);
    event PlayerKicked(uint256 gameId, address player);
    event PlayerNameChanged(address player, string name);

    event NewGame(uint256 gameId);
    event GameOpen(uint256 gameId);
    event GameClose(uint256 gameId);
    event GameStart(uint256 gameId);
    event Turn(uint256 gameId, uint8 playerIndex);

    event CardPicked(uint256 gameId, uint8 playerIndex);
    event CardDealed(uint256 gameId, uint8 turn);

    event GoodGuysWin(uint256 gameId);
    event BadGuysWin(uint256 gameId, string reason);

    // event GoodDeal(uint256 gameId);
    // event FalseDeal(uint256 gameId);

    constructor() Ownable(msg.sender) {}

    function createGame() public {
        Game storage game = games.push();
        game.admin = msg.sender;
        game.running = false;
        game.open = true;
        game.dealNeeded = true;
        game.players.push(msg.sender); // Add msg.sender to the dynamic array
        game.turn = 0;
        game.turnCurrentPlayer = msg.sender;
        game.move = 0;
        game.remainingWires = 0;
        game.bombPosition = euint8.wrap(0);

        uint256 gameId = games.length - 1;
        emit NewGame(gameId);
    }

    function openGame(uint256 gameId) public onlyGameMaster(gameId) {
        games[gameId].open = true;
        emit GameOpen(gameId);
    }

    function closeGame(uint256 gameId) public onlyGameMaster(gameId) {
        games[gameId].open = false;
        emit GameClose(gameId);
    }

    function join(uint256 gameId) public onlyJoinable(gameId) {
        require(games[gameId].players.length < MAX_PLAYERS, "The game has enough players (8)");
        addPlayer(gameId, msg.sender);
        emit PlayerJoined(gameId, msg.sender);
    }

    function leave(uint256 gameId) public onlyJoinable(gameId) {
        removePlayer(gameId, msg.sender);
        emit PlayerLeft(gameId, msg.sender);
    }

    function kick(uint256 gameId, address player) public onlyJoinable(gameId) onlyGameMaster(gameId) {
        removePlayer(gameId, player);
        emit PlayerKicked(gameId, player);
    }

    function addPlayer(uint256 gameId, address player) internal onlyNewPlayer(gameId, player) {
        Game storage game = games[gameId];
        game.players.push(player);
    }

    function removePlayer(uint256 gameId, address player) internal onlyPlayer(gameId, player) {
        bool found = false;
        Game storage game = games[gameId];
        for (uint256 i = 0; i < game.players.length; i += 1) {
            if (found) {
                if (i == game.players.length - 1) {
                    game.players.pop();
                } else {
                    game.players[i] = game.players[i + 1];
                }
            } else if (game.players[i] == player) {
                if (i == game.players.length - 1) {
                    game.players.pop();
                } else {
                    game.players[i] = game.players[i + 1];
                    found = true;
                }
            }
        }
    }

    function getPlayers(uint256 gameId) public view returns (address[] memory) {
        Game storage game = games[gameId];
        return game.players;
    }

    function start(uint256 gameId) public onlyGameOpen(gameId) {
        Game storage game = games[gameId];
        require(game.players.length >= MIN_PLAYERS, "Not enough player to start");
        dealRoles(gameId, uint8(Math.max(game.players.length, 5)));

        game.remainingWires = uint8(game.players.length);
        game.turnCurrentPlayer = game.players[0];
        game.open = false;
        game.running = true;
        game.dealNeeded = true;
        emit GameStart(gameId);
    }

    function dealRoles(uint256 gameId, uint8 numberOfPlayers) internal returns (euint8) {
        Game storage game = games[gameId];

        euint64 random = TFHE.randEuint64();
        // euint64 random = TFHE.asEuint64(0);
        TFHE.allow(random, address(this));
        game.roleRandomness = random;

        euint8 encryptedRoles = _dealRoles(numberOfPlayers, random);
        TFHE.allow(encryptedRoles, address(this));

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedRoles);
        uint256 requestId = Gateway.requestDecryption(cts, this.setRoles.selector, 0, block.timestamp + 1000, false);
        addParamsUint256(requestId, gameId);
    }

    function setRoles(uint256 requestId, uint8 roles) public onlyGateway {
        uint256[] memory params = getParamsUint256(requestId);
        Game storage game = games[params[0]];
        game.roleMask = roles;
    }

    function takeRole(uint256 gameId, uint8 playerIndex) public {
        Game storage game = games[gameId];
        euint8 role = _getRole(game.roleMask, playerIndex, game.roleRandomness);
        ebool boolRole;
        if (game.players.length <= 6) {
            boolRole = TFHE.le(role, 2);
        } else if (game.players.length <= 8) {
            boolRole = TFHE.le(role, 4);
        }
        game.roles[playerIndex] = boolRole;
        TFHE.allow(boolRole, address(this));
        TFHE.allow(boolRole, game.players[playerIndex]);
    }

    function getRole(uint256 gameId, uint256 playerIndex) public view returns (ebool) {
        Game storage game = games[gameId];
        return game.roles[playerIndex];
    }

    function deal(uint256 gameId) public {
        Game storage game = games[gameId];
        require(game.dealNeeded, "Deal is not needed");
        game.cardsRandomness = TFHE.randEuint64();
        TFHE.allow(game.cardsRandomness, address(this));
        euint64 encryptedCards = _dealCards(uint8(game.players.length), 5 - game.turn, game.cardsRandomness);
        TFHE.allow(encryptedCards, address(this));

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedCards);
        uint256 requestId = Gateway.requestDecryption(cts, this.setCards.selector, 0, block.timestamp + 1000, false);
        addParamsUint256(requestId, gameId);
        game.dealNeeded = false;
        emit CardDealed(gameId, game.turn);
    }

    function setCards(uint256 requestId, uint64 cards) public onlyGateway {
        uint256[] memory params = getParamsUint256(requestId);
        Game storage game = games[params[0]];
        game.cardsMask = cards;
    }

    function takeCards(uint256 gameId, uint8 playerIndex) public {
        Game storage game = games[gameId];

        require(game.cardsMask != 0, "Cards mask not set");

        euint64 cardDistribution = _getCards(game.cardsMask, playerIndex, game.players.length, game.cardsRandomness);

        uint8 cardDistributed = 5 - game.turn;
        euint4 wireCards = TFHE.asEuint4(0);
        euint4 hasBomb = TFHE.asEuint4(
            TFHE.ge(cardDistribution, uint64(1 << ((cardDistributed * game.players.length) - 1)))
        );
        euint8 first8 = TFHE.asEuint8(cardDistribution); // wires are on right
        for (uint256 i; i < game.remainingWires; i += 1) {
            ebool hasWire = TFHE.asEbool(TFHE.and(first8, TFHE.asEuint8(1 << i)));
            wireCards = TFHE.add(wireCards, TFHE.asEuint4(hasWire));
        }
        euint4 nullCards = TFHE.sub(TFHE.asEuint4(cardDistributed), TFHE.add(hasBomb, wireCards));

        game.nullCards[playerIndex] = nullCards;
        TFHE.allow(nullCards, address(this));
        TFHE.allow(nullCards, game.players[playerIndex]);
        game.bombCard[playerIndex] = hasBomb;
        TFHE.allow(hasBomb, address(this));
        TFHE.allow(hasBomb, game.players[playerIndex]);
        game.wireCards[playerIndex] = wireCards;
        TFHE.allow(wireCards, address(this));
        TFHE.allow(wireCards, game.players[playerIndex]);
        // TFHE.allow(cards, address(this));
        // TFHE.allow(cards, game.players[playerIndex]);
        // The idea is to create a euint8 where:
        // - Most significant bit is bomb: 10000000
        // - Least significant bits are wires and null cards, separated by a 0: 00011011
        // Examples:
        // Someone with 2 wires and 2 null cards: 00011011
        // Someone with 3 wires and the bomb: 10000001110
        // uint8 cardDistributed = 5 - game.turn;
        // euint8 cards = TFHE.asEuint8(2 ** (cardDistributed) - 1); // For 5 cards, 00011111
        // ebool hasBomb = TFHE.ge(cardDistribution, uint64(1 << ((cardDistributed * game.players.length) - 1)));
        // cards = TFHE.asEuint8(2 ** (cardDistributed) - 1);
        // euint8 first8 = TFHE.asEuint8(cardDistribution); // wires are on right
        // euint8 wireMask = TFHE.asEuint8(2 ** cardDistributed);
        // for (uint256 i; i < game.remainingWires; i += 1) {
        //     ebool hasWire = TFHE.asEbool(TFHE.and(first8, TFHE.asEuint8(1 << i)));
        //     // Remove the null card (or not)
        //     cards = TFHE.shr(cards, TFHE.asEuint8(hasWire));
        //     // Add the wire (or not)
        //     cards = TFHE.select(hasWire, TFHE.or(cards, wireMask), cards);
        // }
        // cards = TFHE.select(hasBomb, TFHE.or(TFHE.shr(cards, 1), TFHE.asEuint8(128)), cards);
        // game.cards[playerIndex] = cards;
        // TFHE.allow(cards, address(this));
        // TFHE.allow(cards, game.players[playerIndex]);
        game.remainingCards[playerIndex] = cardDistributed;
    }

    function pickCard(uint256 gameId, uint8 playerIndex) public onlyPlayerTurn(gameId) {
        Game storage game = games[gameId];
        require(game.remainingCards[playerIndex] > 0, "This player has no cards");
        uint8 remainingCards = game.remainingCards[playerIndex];
        euint8 index = _pickCard(remainingCards, TFHE.randEuint64()); // 0000100 means take the 3rd card
        ebool isBomb = TFHE.and(
            TFHE.asEbool(game.bombCard[playerIndex]),
            TFHE.eq(index, uint8(2 ** (remainingCards - 1)))
        );

        ebool isWire = _isWire(game, index, playerIndex);

        ebool isNull = TFHE.not(TFHE.or(isBomb, isWire));

        euint4 bombCard = TFHE.and(game.bombCard[playerIndex], TFHE.asEuint4(TFHE.not(isBomb)));
        game.bombCard[playerIndex] = bombCard;
        TFHE.allow(bombCard, address(this));
        TFHE.allow(bombCard, game.players[playerIndex]);

        euint4 wireCards = TFHE.sub(game.wireCards[playerIndex], TFHE.asEuint4(isWire));
        game.wireCards[playerIndex] = wireCards;
        TFHE.allow(wireCards, address(this));
        TFHE.allow(wireCards, game.players[playerIndex]);

        euint4 nullCards = TFHE.sub(game.nullCards[playerIndex], TFHE.asEuint4(isNull));
        game.nullCards[playerIndex] = nullCards;
        TFHE.allow(nullCards, address(this));
        TFHE.allow(nullCards, game.players[playerIndex]);

        game.remainingCards[playerIndex] -= 1;
        emit CardPicked(gameId, playerIndex);
    }

    function _isWire(Game storage game, euint8 index, uint8 playerIndex) internal returns (ebool) {
        euint8 rangeShift = TFHE.sub(TFHE.asEuint8(5), game.wireCards[playerIndex]);
        euint8 maskWire = TFHE.shr(TFHE.asEuint8(type(uint8).max), rangeShift);
        return TFHE.asEbool(TFHE.and(index, maskWire));
    }

    function getCards(uint256 gameId, uint256 playerIndex) public view returns (euint4[3] memory) {
        Game storage game = games[gameId];
        return [game.bombCard[playerIndex], game.wireCards[playerIndex], game.nullCards[playerIndex]];
    }

    modifier onlyJoinable(uint256 gameId) {
        require(games[gameId].open && !games[gameId].running, "The game is not joinable");
        _;
    }

    modifier onlyGameOpen(uint256 gameId) {
        Game storage game = games[gameId];
        require(game.open && !game.running, "The game is not open");
        _;
    }

    modifier onlyPlayerTurn(uint256 gameId) {
        bool exists = false;
        Game storage game = games[gameId];
        require(game.turnCurrentPlayer == msg.sender, "This is not your turn!");
        for (uint8 i; i < game.players.length; i++) {
            if (game.players[i] == msg.sender) exists = true;
        }
        require(exists, "This player doesn't exist");
        _;
    }

    modifier onlyPlayer(uint256 gameId, address player) {
        bool exists = false;
        Game storage game = games[gameId];
        for (uint8 i; i < game.players.length; i++) {
            if (game.players[i] == player) exists = true;
        }
        require(exists, "This player doesn't exist");
        _;
    }

    modifier onlyNewPlayer(uint256 gameId, address player) {
        bool newPlayer = true;
        Game storage game = games[gameId];
        for (uint8 i; i < game.players.length; i++) {
            if (game.players[i] == player) newPlayer = false;
        }
        require(newPlayer);
        _;
    }

    modifier onlyGameMaster(uint256 gameId) {
        require(games[gameId].admin == msg.sender, "You're not the game master");
        _;
    }
}
