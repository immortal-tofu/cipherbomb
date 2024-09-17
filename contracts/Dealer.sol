// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "hardhat/console.sol";

import "fhevm/lib/TFHE.sol";

uint256 constant ROUNDS_FOR_64 = 5;
uint8 constant BITS_FOR_64 = 6;

uint256 constant ROUNDS_FOR_8 = 6;
uint8 constant BITS_FOR_8 = 3;

abstract contract Dealer {
    uint8[4] private deltaMasks8 = [0x55, 0x33, 0x0f];
    uint8[4] private deltas8 = [1, 2, 4];

    uint64[5] private deltaMasks64 = [
        0x5555555555555555,
        0x3333333333333333,
        0x0f0f0f0f0f0f0f0f,
        0x00ff00ff00ff00ff,
        0x0000ffff0000ffff
    ];
    uint8[5] private deltas64 = [1, 2, 4, 8, 16];

    function _dealRoles(uint8 playerTotal, euint64 random) internal returns (euint8) {
        require(playerTotal <= 8 && playerTotal >= 4, "Player total must be between 4 and 8");
        uint8 fullOne = type(uint8).max;
        uint8 result = fullOne << playerTotal;
        euint8 bitmask = TFHE.asEuint8(result); // 11110000 for 4 players
        return _randomize8(bitmask, random);
    }

    function _getRole(uint8 bitmask, uint8 index, euint64 random) internal returns (euint8) {
        console.log(bitmask, index, _findNthZero(bitmask, index));
        euint8 mixedCards = TFHE.asEuint8(_findNthZero(bitmask, index));
        // euint8 mixedCards = TFHE.asEuint8(bitmask);
        return _derandomize8(mixedCards, random);
    }

    function _dealCards(uint8 playerTotal, uint8 cardTotal, euint64 random) internal returns (euint64) {
        require(playerTotal <= 8 && playerTotal >= 4, "Player total must be between 4 and 8");
        uint64 fullOne = type(uint64).max;
        uint64 result = fullOne << (playerTotal * cardTotal);
        euint64 bitmask = TFHE.asEuint64(result);
        return _randomize64(bitmask, random);
    }

    function _getCards(
        uint64 bitmask,
        uint8 playerIndex,
        uint256 numberOfPlayers,
        euint64 random
    ) internal returns (euint64) {
        uint64 mask = _findNZero64(bitmask, playerIndex, numberOfPlayers);
        euint64 mixedCards = TFHE.asEuint64(mask);
        uint256 initialShift = uint(BITS_FOR_64) * (ROUNDS_FOR_64 + 1);
        euint64 rand = TFHE.rotr(random, uint8(initialShift));
        return _derandomize64(mixedCards, rand);
    }

    function _pickCard(uint8 remainingCards, euint64 random) internal returns (euint8) {
        uint8 fullOne = type(uint8).max;
        euint8 cards = TFHE.asEuint8(fullOne << remainingCards);
        euint8 randomizedCards = _randomize8(cards, random);
        // Now we want to isolate the LSB using num & (~num + 1) trick
        // Will return 00001000 for 01011000
        euint8 maskPick = TFHE.and(TFHE.not(randomizedCards), TFHE.add(randomizedCards, 1));
        euint8 pick = _derandomize8(maskPick, random);
        return pick;
    }

    function _findNZero64(uint64 input, uint8 index, uint256 numberOfPlayers) internal pure returns (uint64) {
        uint8 count = 0;
        uint64 mask = 1;
        uint64 updatedMask;

        for (uint8 i = 0; i < 64; i++) {
            if ((input & mask) == 0) {
                count++;
                if (count % numberOfPlayers == index) {
                    updatedMask = mask | updatedMask;
                }
            }
            mask <<= 1;
        }
        return updatedMask;
    }

    function _findNthZero(uint8 input, uint8 n) public pure returns (uint8) {
        uint8 count = 0;
        uint8 mask = 1;

        for (uint8 i = 0; i < 8; i++) {
            if ((input & mask) == 0) {
                if (count == n) {
                    return mask;
                }
                count++;
            }
            mask <<= 1;
        }
        return 0;
    }

    function _randomize8(euint8 value, euint64 random) internal returns (euint8) {
        euint64 rand = random;
        for (uint256 i; i < ROUNDS_FOR_8; i += 1) {
            uint256 index = (i % 3);
            rand = TFHE.rotr(rand, BITS_FOR_8);
            value = _deltaSwap8(
                value,
                TFHE.rotr(TFHE.asEuint8(deltaMasks8[index]), TFHE.asEuint8(rand)),
                deltas8[index]
            );
        }
        // Final shift
        rand = TFHE.rotr(rand, BITS_FOR_8);
        return TFHE.rotr(value, TFHE.asEuint8(rand));
    }

    function _derandomize8(euint8 value, euint64 random) internal returns (euint8) {
        euint64 rand = TFHE.rotr(random, uint8(BITS_FOR_8 * (ROUNDS_FOR_8 + 1)));
        value = TFHE.rotl(value, TFHE.asEuint8(rand));
        rand = TFHE.rotl(rand, BITS_FOR_8);
        for (uint256 i = ROUNDS_FOR_8; i > 0; i -= 1) {
            uint256 index = ((i - 1) % 3);
            value = _deltaSwap8(
                value,
                TFHE.rotr(TFHE.asEuint8(deltaMasks8[index]), TFHE.asEuint8(rand)),
                deltas8[index]
            );
            if (i - 1 != 0) rand = TFHE.rotl(rand, uint8(BITS_FOR_8));
        }
        return value;
    }

    function _deltaSwap8(euint8 a, euint8 deltamask, uint8 delta) internal returns (euint8) {
        euint8 partRight = TFHE.and(TFHE.rotr(a, delta), deltamask);
        euint8 partLeft = TFHE.and(TFHE.rotl(a, delta), TFHE.rotr(deltamask, delta));

        return TFHE.or(partLeft, partRight);
    }

    function _randomize64(euint64 value, euint64 random) internal returns (euint64) {
        for (uint256 i; i < ROUNDS_FOR_64; i += 1) {
            uint256 index = (i % 3);
            random = TFHE.rotr(random, BITS_FOR_64);
            value = _deltaSwap64(
                value,
                TFHE.rotr(TFHE.asEuint64(deltaMasks64[index]), TFHE.asEuint8(random)),
                deltas64[index]
            );
        }
        random = TFHE.rotr(random, BITS_FOR_64);
        return TFHE.rotr(value, TFHE.asEuint8(random));
    }

    function _derandomize64(euint64 value, euint64 random) internal returns (euint64) {
        value = TFHE.rotl(value, TFHE.asEuint8(random));
        random = TFHE.rotl(random, BITS_FOR_64);
        for (uint256 i = ROUNDS_FOR_64; i > 0; i -= 1) {
            uint256 index = ((i - 1) % 3);
            value = _deltaSwap64(
                value,
                TFHE.rotr(TFHE.asEuint64(deltaMasks64[index]), TFHE.asEuint8(random)),
                deltas64[index]
            );
            random = TFHE.rotl(random, uint8(BITS_FOR_64));
        }
        return value;
    }

    function _deltaSwap64(euint64 a, euint64 deltamask, uint8 delta) internal returns (euint64) {
        euint64 partRight = TFHE.and(TFHE.rotr(a, delta), deltamask);
        euint64 partLeft = TFHE.and(TFHE.rotl(a, delta), TFHE.rotr(deltamask, delta));

        return TFHE.or(partLeft, partRight);
    }
}
