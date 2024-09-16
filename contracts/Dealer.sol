// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "hardhat/console.sol";

import "fhevm/lib/TFHE.sol";

uint constant ROUNDS_FOR_64 = 10;
uint8 constant BITS_FOR_64 = 6;

uint constant ROUNDS_FOR_8 = 9;
uint8 constant BITS_FOR_8 = 3;

abstract contract Dealer {
    uint64[3] private deltaMasks8 = [0x55, 0x33, 0x0f];
    uint8[3] private deltas8 = [1, 2, 4];

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
        euint64 rand = random;
        for (uint i; i < ROUNDS_FOR_8; i += 1) {
            uint index = (i % 3);
            rand = TFHE.rotr(rand, BITS_FOR_8);
            bitmask = _deltaSwap8(
                bitmask,
                TFHE.rotr(TFHE.asEuint8(deltaMasks8[index]), TFHE.asEuint8(rand)),
                deltas8[index]
            );
        }
        // Final shift
        rand = TFHE.rotr(rand, BITS_FOR_8);
        return TFHE.rotr(bitmask, TFHE.asEuint8(rand));
    }

    function _getRole(uint8 bitmask, uint8 index, euint64 random) internal returns (euint8) {
        console.log(bitmask, index, _findNthZero(bitmask, index));
        euint8 mixedCards = TFHE.asEuint8(_findNthZero(bitmask, index));
        // euint8 mixedCards = TFHE.asEuint8(bitmask);
        euint64 rand = TFHE.rotr(random, uint8(BITS_FOR_8 * (ROUNDS_FOR_8 + 1)));
        mixedCards = TFHE.rotl(mixedCards, TFHE.asEuint8(rand));
        rand = TFHE.rotl(rand, BITS_FOR_8);
        for (uint i = ROUNDS_FOR_8; i > 0; i -= 1) {
            uint index = ((i - 1) % 3);
            mixedCards = _deltaSwap8(
                mixedCards,
                TFHE.rotr(TFHE.asEuint8(deltaMasks8[index]), TFHE.asEuint8(rand)),
                deltas8[index]
            );
            rand = TFHE.rotl(rand, uint8(BITS_FOR_8));
        }
        return mixedCards;
    }

    function _dealCards(uint8 playerTotal, uint8 cardTotal, euint64 random) internal returns (euint64) {
        require(playerTotal <= 8 && playerTotal >= 4, "Player total must be between 4 and 8");
        uint64 fullOne = type(uint64).max;
        uint64 result = fullOne << (playerTotal * cardTotal);
        euint64 bitmask = TFHE.asEuint64(result);
        euint64 rand = random;
        for (uint i; i < ROUNDS_FOR_64; i += 1) {
            uint index = (i % 3);
            rand = TFHE.rotr(rand, BITS_FOR_64);
            bitmask = _deltaSwap64(
                bitmask,
                TFHE.rotr(TFHE.asEuint64(deltaMasks64[index]), TFHE.asEuint8(rand)),
                deltas64[index]
            );
        }
        rand = TFHE.rotr(rand, BITS_FOR_64);
        return TFHE.rotr(bitmask, TFHE.asEuint8(rand));
    }

    function _getCards(uint64 bitmask, uint8 index, uint8 cards, euint64 random) internal returns (euint64) {
        uint64 mask = _findNZero64(bitmask, index * cards, cards);
        euint64 mixedCards = TFHE.asEuint64(mask);
        uint initialShift = uint(BITS_FOR_64) * (ROUNDS_FOR_64 + 1);
        euint64 rand = TFHE.rotr(random, uint8(initialShift));
        mixedCards = TFHE.rotl(mixedCards, TFHE.asEuint8(rand));
        rand = TFHE.rotl(rand, BITS_FOR_64);
        for (uint i = ROUNDS_FOR_64; i > 0; i -= 1) {
            uint index = ((i - 1) % 3);
            mixedCards = _deltaSwap64(
                mixedCards,
                TFHE.rotr(TFHE.asEuint64(deltaMasks64[index]), TFHE.asEuint8(rand)),
                deltas64[index]
            );
            rand = TFHE.rotl(rand, uint8(BITS_FOR_64));
        }

        return mixedCards;
    }

    function _findNZero64(uint64 input, uint8 from, uint8 total) public pure returns (uint64) {
        uint8 count = 0;
        uint64 mask = 1;
        uint64 updatedMask;

        for (uint8 i = 0; i < 64; i++) {
            if ((input & mask) == 0) {
                count++;
                if (count >= from + 1) {
                    updatedMask = mask | updatedMask;
                    if (count == from + total) {
                        return updatedMask;
                    }
                }
            }
            mask <<= 1;
        }
        return 0;
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

    function _deltaSwap8(euint8 a, euint8 deltamask, uint8 delta) internal returns (euint8) {
        euint8 partRight = TFHE.and(TFHE.rotr(a, delta), deltamask);
        euint8 partLeft = TFHE.and(TFHE.rotl(a, delta), TFHE.rotr(deltamask, delta));

        return TFHE.or(partLeft, partRight);
    }

    function _deltaSwap64(euint64 a, euint64 deltamask, uint8 delta) internal returns (euint64) {
        euint64 partRight = TFHE.and(TFHE.rotr(a, delta), deltamask);
        euint64 partLeft = TFHE.and(TFHE.rotl(a, delta), TFHE.rotr(deltamask, delta));

        return TFHE.or(partLeft, partRight);
    }
}
