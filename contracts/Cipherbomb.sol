// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "./Dealer.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Cipherbomb is Dealer, GatewayCaller, Ownable2Step {
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
        ebool[] roles;
        uint8 roleMask;
        uint8 turn;
        address turnCurrentPlayer;
        uint8 move;
        uint8 remainingWires;
        euint8[] wirePositions;
        euint8 bombPosition;
        euint64 randomness;
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
        game.turnCurrentPlayer = msg.sender;
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

    function leave(uint gameId) public onlyJoinable(gameId) {
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

    function getPlayers(uint gameId) public view returns (address[] memory) {
        Game storage game = games[gameId];
        return game.players;
    }

    function start(uint gameId) public onlyGameOpen(gameId) {
        Game storage game = games[gameId];
        require(game.players.length >= MIN_PLAYERS, "Not enough player to start");
        giveRoles(gameId, uint8(Math.max(game.players.length, 5)));

        game.remainingWires = uint8(game.players.length);
        game.turnCurrentPlayer = game.players[0];
        game.open = false;
        game.running = true;
        emit GameStart(gameId);
    }

    function giveRoles(uint gameId, uint8 numberOfPlayers) internal returns (euint8) {
        Game storage game = games[gameId];

        euint64 random = TFHE.randEuint64();
        // euint64 random = TFHE.asEuint64(0);
        TFHE.allow(random, address(this));
        game.randomness = random;

        euint8 encryptedRole = _getMaskRole(numberOfPlayers, random);
        TFHE.allow(encryptedRole, address(this));

        uint256[] memory cts = new uint256[](2);
        cts[0] = Gateway.toUint256(encryptedRole);
        cts[1] = Gateway.toUint256(random);
        uint256 requestId = Gateway.requestDecryption(cts, this.setRoles.selector, 0, block.timestamp + 1000, false);
        addParamsUint256(requestId, gameId);
    }

    function setRoles(uint256 requestId, uint8 roles, uint64 rand) public onlyGateway returns (uint8) {
        uint256[] memory params = getParamsUint256(requestId);
        Game storage game = games[params[0]];
        console.log("decrypted", roles, "rand", rand);
        game.roleMask = roles;
    }

    function takeRole(uint256 gameId, uint8 index) public {
        Game storage game = games[gameId];
        euint8 role = _getRole(game.roleMask, index, game.randomness);
        ebool boolRole;
        if (game.players.length <= 6) {
            boolRole = TFHE.le(role, 2);
        } else if (game.players.length <= 8) {
            boolRole = TFHE.le(role, 4);
        }
        game.roles.push(boolRole);
        TFHE.allow(boolRole, address(this));
        TFHE.allow(boolRole, game.players[index]);
    }

    function getRole(uint gameId, uint index) public view returns (ebool) {
        Game storage game = games[gameId];
        return game.roles[index];
    }

    modifier onlyJoinable(uint gameId) {
        require(games[gameId].open && !games[gameId].running, "The game is not joinable");
        _;
    }

    modifier onlyGameOpen(uint gameId) {
        Game storage game = games[gameId];
        require(game.open && !game.running, "The game is not open");
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
