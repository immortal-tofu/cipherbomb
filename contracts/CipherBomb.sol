// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.19;

import "fhevm/lib/TFHE.sol";
import "fhevm/abstracts/EIP712WithModifier.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract CipherBomb is Ownable, EIP712WithModifier {
    uint public constant MIN_PLAYERS = 4;
    uint public constant MAX_PLAYERS = 6;

    enum CardType {
        WIRE,
        BOMB,
        NEUTRAL
    }

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

    mapping(address => string) public name;
    mapping(address => ebool) roles;
    mapping(address => Cards) cards;

    struct Cards {
        euint8 bomb;
        euint8 wires;
        euint8 neutrals;
        euint8 total;
    }

    event PlayerJoined(address player);
    event PlayerLeft(address player);
    event PlayerKicked(address player);
    event PlayerNameChanged(address player, string name);

    event GameOpen();
    event GameStart();
    event Turn(uint8 index);
    event CardPicked(uint8 cardType);

    event GoodGuysWin();
    event BadGuysWin(string reason);

    event GoodDeal();
    event FalseDeal();

    constructor() EIP712WithModifier("Authorization token", "1") {
        gameRunning = false;
        open();
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
        addPlayer(owner());

        emit GameOpen();
    }

    function start() public onlyGameOpen {
        require(numberOfPlayers >= MIN_PLAYERS, "Not enough player to start");
        gameOpen = false;
        gameRunning = true;
        remainingWires = numberOfPlayers;
        turnCurrentPlayer = players[0];
        giveRoles();
        emit GameStart();
    }

    function join() public onlyGameOpen {
        require(numberOfPlayers < MAX_PLAYERS, "The game has enough players (8)");
        addPlayer(msg.sender);
        emit PlayerJoined(msg.sender);
    }

    function addPlayer(address player) internal onlyNewPlayer(player) {
        players[numberOfPlayers] = player;
        numberOfPlayers++;
    }

    function leave() public onlyGameOpen onlyOwner {
        removePlayer(msg.sender);
        emit PlayerLeft(msg.sender);
    }

    function kick(address player) public onlyGameOpen onlyOwner {
        removePlayer(player);
        emit PlayerKicked(player);
    }

    function removePlayer(address player) internal onlyPlayer(player) {
        bool found = false;
        for (uint i = 0; i < players.length; i += 1) {
            if (players[i] == player) {
                delete players[i];
                players[i] = players[i + 1];
                found = true;
            } else if (found) {
                players[i] = players[i + 1];
            }
        }
        numberOfPlayers--;
    }

    function setName(string calldata playername) public {
        name[msg.sender] = playername;
        emit PlayerNameChanged(msg.sender, playername);
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
            euint8 total = bomb + wires + neutrals;
            cards[players[i]] = Cards(bomb, wires, neutrals, total);
            dealIsCorrect = TFHE.and(dealIsCorrect, TFHE.le(wires + bomb, turnCardLimit()));
        }
        turnDealNeeded = !TFHE.decrypt(dealIsCorrect);
        if (turnDealNeeded) {
            emit FalseDeal();
        } else {
            emit GoodDeal();
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
            ebool role; // 1 = Nice guy / 0 = Bad guy
            for (uint8 j; j < 2; j++) {
                role = TFHE.ne(positions[j], i); // If equal, role is bad guy (so = 0)
            }
            roles[players[i]] = role;
        }
        gameRoleDealNeeded = false;
    }

    function getRole(
        bytes32 publicKey,
        bytes calldata signature
    )
        public
        view
        onlyGameRunning
        onlyPlayer(msg.sender)
        onlySignedPublicKey(publicKey, signature)
        returns (bytes memory)
    {
        address player = msg.sender;
        return TFHE.reencrypt(roles[player], publicKey);
    }

    function getCards() public view onlyGameRunning returns (uint8[] memory) {
        uint8[] memory tableCards = new uint8[](numberOfPlayers);
        for (uint8 i = 0; i < numberOfPlayers; i++) {
            address player = players[i];
            if (TFHE.isInitialized(cards[player].total)) {
                tableCards[i] = TFHE.decrypt(cards[player].total);
            }
        }
        return tableCards;
    }

    function getMyCards(
        bytes32 publicKey,
        bytes calldata signature
    )
        public
        view
        onlyGameRunning
        onlyPlayer(msg.sender)
        onlySignedPublicKey(publicKey, signature)
        returns (bytes[3] memory)
    {
        address player = msg.sender;
        bytes memory wires = TFHE.reencrypt(cards[player].wires, publicKey);
        bytes memory bomb = TFHE.reencrypt(cards[player].bomb, publicKey);
        bytes memory neutrals = TFHE.reencrypt(cards[player].neutrals, publicKey);
        return [wires, bomb, neutrals];
    }

    function endGame() internal {
        gameRunning = false;
        open();
    }

    function takeCard(address player) public onlyGameRunning onlyTurnRunning onlyCurrentPlayer(msg.sender) {
        require(TFHE.decrypt(TFHE.gt(cards[player].total, 0)));
        euint8 cardToTake = TFHE.shr(TFHE.randEuint8(), 5); // 3 bits of randomness
        euint8 correctedCard = TFHE.cmux(
            TFHE.lt(cardToTake, cards[player].total),
            cardToTake,
            cardToTake - cards[player].total
        );
        ebool cardIsWire = TFHE.and(TFHE.gt(cards[player].wires, 0), TFHE.lt(correctedCard, cards[player].wires));
        ebool cardIsBomb = TFHE.and(TFHE.eq(cards[player].bomb, 1), TFHE.eq(correctedCard, cards[player].wires));

        cards[player].wires = TFHE.cmux(cardIsWire, TFHE.sub(cards[player].wires, 1), cards[player].wires);
        cards[player].bomb = TFHE.cmux(cardIsBomb, TFHE.sub(cards[player].bomb, 1), cards[player].bomb);
        cards[player].neutrals = TFHE.cmux(
            TFHE.or(cardIsBomb, cardIsWire),
            cards[player].neutrals,
            TFHE.sub(cards[player].neutrals, 1)
        );
        cards[player].total = TFHE.sub(cards[player].total, 1);

        euint8 eCardType = TFHE.asEuint8(uint8(CardType.NEUTRAL));
        eCardType = TFHE.cmux(cardIsWire, TFHE.asEuint8(uint8(CardType.WIRE)), eCardType);
        eCardType = TFHE.cmux(cardIsBomb, TFHE.asEuint8(uint8(CardType.BOMB)), eCardType);

        turnMove++;

        uint8 cardType = TFHE.decrypt(eCardType);

        if (cardType == uint8(CardType.BOMB)) {
            emit BadGuysWin("bomb");
            endGame();
            return;
        }

        if (cardType == uint8(CardType.WIRE)) {
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
                emit BadGuysWin("cards");
                endGame();
                return;
            }
            emit Turn(turnIndex);
            turnMove = 0;
            turnDealNeeded = true;
        }

        emit CardPicked(cardType);
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
