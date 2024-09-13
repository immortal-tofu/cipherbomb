// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Cipherbomb is Ownable2Step {
    uint public constant MIN_PLAYERS = 4;
    uint public constant MAX_PLAYERS = 8;

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
        uint8 turn;
        uint8 move;
        uint8 remainingWires;
        euint8[] wirePositions;
        euint8 bombPosition;
    }

    Game[] public games;

    mapping(address => string) nicknames;

    event PlayerJoined(uint gameId, address player);
    event PlayerLeft(uint gameId, address player);
    event PlayerKicked(uint gameId, address player);
    event PlayerNameChanged(address player, string name);

    event NewGame(uint gameId);
    event GameOpen(uint gameId);
    event GameClose(uint gameId);
    event GameStart(uint gameId);
    event Turn(uint gameId, uint8 index);
    event CardPicked(uint gameId, uint8 cardType);

    event GoodGuysWin(uint gameId);
    event BadGuysWin(uint gameId, string reason);

    // event GoodDeal(uint gameId);
    // event FalseDeal(uint gameId);

    constructor() Ownable(msg.sender) {}

    function createGame() public {
        Game storage game = games.push();
        game.admin = msg.sender;
        game.running = false;
        game.open = true;
        game.dealNeeded = true;
        game.players.push(msg.sender); // Add msg.sender to the dynamic array
        game.turn = 0;
        game.move = 0;
        game.remainingWires = 0;
        game.wirePositions = [
            euint8.wrap(0),
            euint8.wrap(0),
            euint8.wrap(0),
            euint8.wrap(0),
            euint8.wrap(0),
            euint8.wrap(0),
            euint8.wrap(0),
            euint8.wrap(0)
        ];
        game.bombPosition = euint8.wrap(0);

        uint gameId = games.length - 1;
        emit NewGame(gameId);
    }

    function openGame(uint gameId) public onlyGameMaster(gameId) {
        games[gameId].open = true;
        emit GameOpen(gameId);
    }

    function closeGame(uint gameId) public onlyGameMaster(gameId) {
        games[gameId].open = false;
        emit GameClose(gameId);
    }

    function join(uint gameId) public onlyJoinable(gameId) {
        require(games[gameId].players.length < MAX_PLAYERS, "The game has enough players (8)");
        addPlayer(gameId, msg.sender);
        emit PlayerJoined(gameId, msg.sender);
    }

    function leave(uint gameId) public onlyJoinable(gameId) onlyOwner {
        removePlayer(gameId, msg.sender);
        emit PlayerLeft(gameId, msg.sender);
    }

    function kick(uint gameId, address player) public onlyJoinable(gameId) onlyGameMaster(gameId) {
        removePlayer(gameId, player);
        emit PlayerKicked(gameId, player);
    }

    function addPlayer(uint gameId, address player) internal onlyNewPlayer(gameId, player) {
        Game storage game = games[gameId];
        game.players.push(player);
    }

    function removePlayer(uint gameId, address player) internal onlyPlayer(gameId, player) {
        bool found = false;
        Game storage game = games[gameId];
        for (uint i = 0; i < game.players.length; i += 1) {
            if (game.players[i] == player) {
                delete game.players[i];
                game.players[i] = game.players[i + 1];
                found = true;
            } else if (found) {
                game.players[i] = game.players[i + 1];
            }
        }
    }

    modifier onlyJoinable(uint gameId) {
        require(games[gameId].open && !games[gameId].running, "The game is not open");
        _;
    }

    modifier onlyPlayer(uint gameId, address player) {
        bool exists = false;
        Game storage game = games[gameId];
        for (uint8 i; i < game.players.length; i++) {
            if (game.players[i] == player) exists = true;
        }
        require(exists, "This player doesn't exist");
        _;
    }

    modifier onlyNewPlayer(uint gameId, address player) {
        bool newPlayer = true;
        Game storage game = games[gameId];
        for (uint8 i; i < game.players.length; i++) {
            if (game.players[i] == player) newPlayer = false;
        }
        require(newPlayer);
        _;
    }

    modifier onlyGameMaster(uint gameId) {
        require(games[gameId].admin == msg.sender, "You're not the game master");
        _;
    }
}
