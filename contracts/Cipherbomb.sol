// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Dealer.sol";

contract Cipherbomb is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, Dealer, GatewayCaller, Ownable2Step {
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
        euint4 lastCardPicked;
        uint8 turn;
        address turnCurrentPlayer;
        uint8 turnIndex;
        euint64 roleRandomness;
    }

    struct Cards {
        uint8 remainingWires;
        uint64 mask;
        euint64 randomness;
        euint4[8] nullCards;
        euint4[8] wireCards;
        euint4[8] bombCard;
        uint8[8] remainingCards;
    }

    Game[] public games;
    Cards[] public cards;

    mapping(address => string) nicknames; // TODO: integrate later

    event PlayerJoined(uint256 indexed gameId, address indexed player);
    event PlayerLeft(uint256 indexed gameId, address indexed player);
    event PlayerKicked(uint256 indexed gameId, address indexed player);
    event PlayerNameChanged(address indexed player, string name);

    event NewGame(uint256 indexed gameId);
    event GameOpen(uint256 indexed gameId);
    event GameClose(uint256 indexed gameId);
    event GameStart(uint256 indexed gameId);
    event Turn(uint256 indexed gameId, uint8 playerIndex);

    event CardPicked(uint256 indexed gameId, uint256 playerIndex, string cardType);
    event CardDealed(uint256 indexed gameId, uint8 turn);

    event GoodGuysWin(uint256 indexed gameId);
    event BadGuysWin(uint256 indexed gameId, string reason);

    // event GoodDeal(uint256 gameId);
    // event FalseDeal(uint256 gameId);

    constructor() Ownable(msg.sender) {}

    function createGame() external {
        Game storage game = games.push();
        game.admin = msg.sender;
        game.running = false;
        game.open = true;
        game.dealNeeded = true;
        game.players.push(msg.sender); // Add msg.sender to the dynamic array
        game.turn = 0;
        game.turnCurrentPlayer = msg.sender;
        game.turnIndex = 0;

        Cards storage gameCards = cards.push();
        gameCards.remainingWires = 0;

        uint256 gameId = games.length - 1;
        emit NewGame(gameId);
    }

    function openGame(uint256 gameId) external onlyGameMaster(gameId) {
        games[gameId].open = true;
        emit GameOpen(gameId);
    }

    function closeGame(uint256 gameId) external onlyGameMaster(gameId) {
        games[gameId].open = false;
        emit GameClose(gameId);
    }

    function join(uint256 gameId) external onlyOpen(gameId) {
        require(games[gameId].players.length < MAX_PLAYERS, "The game has enough players (8)");
        _addPlayer(gameId, msg.sender);
        emit PlayerJoined(gameId, msg.sender);
    }

    function leave(uint256 gameId) external onlyOpen(gameId) {
        _removePlayer(gameId, msg.sender);
        emit PlayerLeft(gameId, msg.sender);
    }

    function kick(uint256 gameId, address player) external onlyGameMaster(gameId) onlyOpen(gameId) {
        _removePlayer(gameId, player);
        emit PlayerKicked(gameId, player);
    }

    function _addPlayer(uint256 gameId, address player) internal onlyNewPlayer(gameId, player) {
        Game storage game = games[gameId];
        game.players.push(player);
    }

    function _removePlayer(uint256 gameId, address player) internal onlyPlayer(gameId, player) {
        bool found = false;
        Game storage game = games[gameId];
        uint256 playerLen = game.players.length;
        for (uint256 i; i < playerLen; i += 1) {
            if (found) {
                if (i == playerLen - 1) {
                    game.players.pop();
                } else {
                    game.players[i] = game.players[i + 1];
                }
            } else if (game.players[i] == player) {
                if (i == playerLen - 1) {
                    game.players.pop();
                } else {
                    game.players[i] = game.players[i + 1];
                    found = true;
                }
            }
        }
    }

    function getPlayers(uint256 gameId) external view returns (address[] memory) {
        Game storage game = games[gameId];
        return game.players;
    }

    function start(uint256 gameId) external onlyOpen(gameId) {
        Game storage game = games[gameId];
        Cards storage gameCards = cards[gameId];
        require(game.players.length >= MIN_PLAYERS, "Not enough player to start");
        dealRoles(gameId, uint8(Math.max(game.players.length, 5)));

        gameCards.remainingWires = uint8(game.players.length);
        game.turnCurrentPlayer = game.players[0];
        game.open = false;
        game.running = true;
        game.dealNeeded = true;
        emit GameStart(gameId);
    }

    function dealRoles(uint256 gameId, uint8 numberOfPlayers) internal {
        Game storage game = games[gameId];

        euint64 random = TFHE.randEuint64();
        TFHE.allowThis(random);
        game.roleRandomness = random;

        euint8 encryptedRoles = _dealRoles(numberOfPlayers, random);
        TFHE.allowThis(encryptedRoles);

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedRoles);
        uint256 requestId = Gateway.requestDecryption(cts, this.setRoles.selector, 0, block.timestamp + 1000, false);
        addParamsUint256(requestId, gameId);
    }

    function setRoles(uint256 requestId, uint8 roles) external onlyGateway {
        uint256[] memory params = getParamsUint256(requestId);
        Game storage game = games[params[0]];
        game.roleMask = roles;
    }

    function takeRole(uint256 gameId, uint8 playerIndex) external {
        Game storage game = games[gameId];
        euint8 role = _getRole(game.roleMask, playerIndex, game.roleRandomness);
        ebool boolRole;
        if (game.players.length <= 6) {
            boolRole = TFHE.le(role, 2);
        } else if (game.players.length <= 8) {
            boolRole = TFHE.le(role, 4);
        }
        game.roles[playerIndex] = boolRole;
        TFHE.allowThis(boolRole);
        TFHE.allow(boolRole, game.players[playerIndex]);
    }

    function getRole(uint256 gameId, uint256 playerIndex) external view returns (ebool) {
        Game storage game = games[gameId];
        return game.roles[playerIndex];
    }

    function deal(uint256 gameId) external onlyDealNeeded(gameId) {
        Game storage game = games[gameId];
        Cards storage gameCards = cards[gameId];
        require(game.dealNeeded, "Deal is not needed");
        gameCards.randomness = TFHE.randEuint64();
        TFHE.allow(gameCards.randomness, address(this));
        euint64 encryptedCards = _dealCards(uint8(game.players.length), 5 - game.turn, gameCards.randomness);
        TFHE.allow(encryptedCards, address(this));

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(encryptedCards);
        uint256 requestId = Gateway.requestDecryption(cts, this.setCards.selector, 0, block.timestamp + 1000, false);
        addParamsUint256(requestId, gameId);
        game.dealNeeded = false;
        emit CardDealed(gameId, game.turn);
    }

    function setCards(uint256 requestId, uint64 mask) external onlyGateway {
        uint256[] memory params = getParamsUint256(requestId);
        Cards storage gameCards = cards[params[0]];
        gameCards.mask = mask;
    }

    function takeCards(uint256 gameId, uint8 playerIndex) external onlyPlayerTurn(gameId) {
        Game storage game = games[gameId];
        Cards storage gameCards = cards[gameId];

        require(gameCards.mask != 0, "Cards mask not set");

        euint64 cardDistribution = _getCards(gameCards.mask, playerIndex, game.players.length, gameCards.randomness);

        uint8 cardDistributed = 5 - game.turn;
        euint4 wireCards = TFHE.asEuint4(0);
        euint4 hasBomb = TFHE.asEuint4(
            TFHE.ge(cardDistribution, uint64(1 << ((cardDistributed * game.players.length) - 1)))
        );
        euint8 first8 = TFHE.asEuint8(cardDistribution); // wires are on right
        for (uint256 i; i < gameCards.remainingWires; i += 1) {
            ebool hasWire = TFHE.asEbool(TFHE.and(first8, TFHE.asEuint8(1 << i)));
            wireCards = TFHE.add(wireCards, TFHE.asEuint4(hasWire));
        }
        euint4 nullCards = TFHE.sub(TFHE.asEuint4(cardDistributed), TFHE.add(hasBomb, wireCards));

        gameCards.nullCards[playerIndex] = nullCards;
        TFHE.allow(nullCards, address(this));
        TFHE.allow(nullCards, game.players[playerIndex]);
        gameCards.bombCard[playerIndex] = hasBomb;
        TFHE.allow(hasBomb, address(this));
        TFHE.allow(hasBomb, game.players[playerIndex]);
        gameCards.wireCards[playerIndex] = wireCards;
        TFHE.allow(wireCards, address(this));
        TFHE.allow(wireCards, game.players[playerIndex]);
        gameCards.remainingCards[playerIndex] = cardDistributed;
    }

    function pickCard(uint256 gameId, uint8 playerIndex) external onlyPlayerTurn(gameId) {
        Game storage game = games[gameId];
        Cards storage gameCards = cards[gameId];
        require(gameCards.remainingCards[playerIndex] > 0, "This player has no cards");
        uint8 remainingCards = gameCards.remainingCards[playerIndex];
        euint8 index = _pickCard(remainingCards, TFHE.randEuint64()); // 0000100 means take the 3rd card

        ebool isBomb = TFHE.and(
            TFHE.asEbool(gameCards.bombCard[playerIndex]),
            TFHE.eq(index, uint8(2 ** (remainingCards - 1)))
        );
        ebool isWire = _isWire(gameCards, index, playerIndex);
        ebool isNull = TFHE.not(TFHE.or(isBomb, isWire));

        _updateCards(game, gameCards, playerIndex, isBomb, isWire, isNull);

        gameCards.remainingCards[playerIndex] -= 1;

        euint4 cardPicked = TFHE.select(
            isBomb,
            TFHE.asEuint4(2),
            TFHE.select(isWire, TFHE.asEuint4(1), TFHE.asEuint4(0))
        );
        game.lastCardPicked = cardPicked;
        TFHE.allow(cardPicked, address(this));

        _decryptCardPicked(gameId, playerIndex, cardPicked);
    }

    function _updateCards(
        Game storage game,
        Cards storage gameCards,
        uint256 playerIndex,
        ebool isBomb,
        ebool isWire,
        ebool isNull
    ) internal {
        euint4 bombCard = TFHE.and(gameCards.bombCard[playerIndex], TFHE.asEuint4(TFHE.not(isBomb)));
        gameCards.bombCard[playerIndex] = bombCard;
        TFHE.allow(bombCard, address(this));
        TFHE.allow(bombCard, game.players[playerIndex]);

        euint4 wireCards = TFHE.sub(gameCards.wireCards[playerIndex], TFHE.asEuint4(isWire));
        gameCards.wireCards[playerIndex] = wireCards;
        TFHE.allow(wireCards, address(this));
        TFHE.allow(wireCards, game.players[playerIndex]);

        euint4 nullCards = TFHE.sub(gameCards.nullCards[playerIndex], TFHE.asEuint4(isNull));
        gameCards.nullCards[playerIndex] = nullCards;
        TFHE.allow(nullCards, address(this));
        TFHE.allow(nullCards, game.players[playerIndex]);
    }

    function _decryptCardPicked(uint256 gameId, uint256 playerIndex, euint4 cardPicked) internal {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(cardPicked);
        uint256 requestId = Gateway.requestDecryption(
            cts,
            this.setPickedCard.selector,
            0,
            block.timestamp + 1000,
            false
        );
        addParamsUint256(requestId, gameId);
        addParamsUint256(requestId, playerIndex);
    }

    function setPickedCard(uint256 requestId, uint8 card) external onlyGateway {
        uint256[] memory params = getParamsUint256(requestId);
        uint256 gameId = params[0];
        uint256 playerIndex = params[1];
        Game storage game = games[gameId];
        Cards storage gameCards = cards[gameId];
        if (card == 1) {
            uint8 remainingWires = gameCards.remainingWires - 1;
            gameCards.remainingWires = remainingWires;
            emit CardPicked(params[0], playerIndex, "wire");
            if (remainingWires == 0) {
                emit GoodGuysWin(gameId);
                _endGame(game);
            }
        } else if (card == 2) {
            emit CardPicked(params[0], playerIndex, "bomb");
            emit BadGuysWin(gameId, "bomb");
            _endGame(game);
            return;
        } else {
            emit CardPicked(params[0], playerIndex, "null");
            return;
        }

        game.turnCurrentPlayer = game.players[playerIndex];
        if (game.turnIndex + 1 == game.players.length) {
            _nextTurn(game, gameCards);
        } else {
            game.turnIndex += 1;
        }
    }

    function _nextTurn(Game storage game, Cards storage gameCards) internal {
        if (game.turn + 1 == 4) {
            _endGame(game);
            return;
        }
        game.turn += 1;
        game.dealNeeded = true;
        delete gameCards.nullCards;
        delete gameCards.wireCards;
        delete gameCards.bombCard;
        delete gameCards.mask;
    }

    function _endGame(Game storage game) internal {
        game.running = false;
    }

    function _isWire(Cards storage gameCards, euint8 index, uint8 playerIndex) internal returns (ebool) {
        euint8 rangeShift = TFHE.sub(TFHE.asEuint8(5), gameCards.wireCards[playerIndex]);
        euint8 maskWire = TFHE.shr(TFHE.asEuint8(type(uint8).max), rangeShift);
        return TFHE.asEbool(TFHE.and(index, maskWire));
    }

    function getCards(uint256 gameId, uint256 playerIndex) external view returns (euint4[3] memory) {
        Cards memory gameCards = cards[gameId];
        return [gameCards.bombCard[playerIndex], gameCards.wireCards[playerIndex], gameCards.nullCards[playerIndex]];
    }

    modifier onlyDealNeeded(uint256 gameId) {
        Game storage game = games[gameId];
        require(game.dealNeeded && game.running, "The game doesn't need a deal");
        _;
    }

    modifier onlyOpen(uint256 gameId) {
        Game memory game = games[gameId];
        require(game.open && !game.running, "The game is not open");
        _;
    }

    modifier onlyRunning(uint256 gameId) {
        require(games[gameId].running, "The game is not running");
        _;
    }

    modifier onlyPlayerTurn(uint256 gameId) {
        bool exists = false;
        Game memory game = games[gameId];
        require(game.running, "This game is not running");
        require(game.turnCurrentPlayer == msg.sender, "This is not your turn!");
        uint256 playerLen = game.players.length;
        for (uint8 i; i < playerLen; i++) {
            if (game.players[i] == msg.sender) exists = true;
        }
        require(exists, "This player doesn't exist");
        _;
    }

    modifier onlyPlayer(uint256 gameId, address player) {
        bool exists = false;
        Game memory game = games[gameId];
        uint256 playerLen = game.players.length;
        for (uint8 i; i < playerLen; i++) {
            if (game.players[i] == player) exists = true;
        }
        require(exists, "This player doesn't exist");
        _;
    }

    modifier onlyNewPlayer(uint256 gameId, address player) {
        bool newPlayer = true;
        Game memory game = games[gameId];
        uint256 playerLen = game.players.length;
        for (uint8 i; i < playerLen; i++) {
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
