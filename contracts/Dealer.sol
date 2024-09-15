// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "hardhat/console.sol";

import "fhevm/lib/TFHE.sol";

uint constant ROUNDS_FOR_8 = 9;
uint8 constant BITS_FOR_8 = 3;

contract Dealer {
    uint64[3] private deltaMasks = [0x55, 0x33, 0x0f];

    uint8[3] private deltas = [1, 2, 4];

    // cards should be
    function _getMaskRole(uint8 playerTotal, euint64 random) internal returns (euint8) {
        require(playerTotal <= 8 && playerTotal >= 4, "Player total must be between 4 and 8");
        uint8 fullOne = type(uint8).max;
        uint8 result = fullOne << playerTotal;
        euint8 bitmask = TFHE.asEuint8(result); // 11110000 for 4 players
        euint64 rand = random;
        uint loop;
        for (uint i; i < ROUNDS_FOR_8; i += 1) {
            uint index = (i % 3);
            rand = TFHE.rotr(rand, BITS_FOR_8);
            bitmask = _deltaSwap8(
                bitmask,
                TFHE.rotr(TFHE.asEuint8(deltaMasks[index]), TFHE.asEuint8(rand)),
                deltas[index]
            );
            loop++;
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
        uint loop;
        for (uint i = ROUNDS_FOR_8; i > 0; i -= 1) {
            uint index = ((i - 1) % 3);
            mixedCards = _deltaSwap8(
                mixedCards,
                TFHE.rotr(TFHE.asEuint8(deltaMasks[index]), TFHE.asEuint8(rand)),
                deltas[index]
            );
            rand = TFHE.rotl(rand, uint8(BITS_FOR_8));
            loop++;
        }
        console.log("decrypt loop", loop);
        return mixedCards;
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

    function _xor(euint8 a, euint8 b) internal returns (euint8) {
        return TFHE.or(TFHE.and(TFHE.not(a), b), TFHE.and(a, TFHE.not(b)));
    }

    function _deltaSwap8(euint8 a, euint8 deltamask, uint8 delta) internal returns (euint8) {
        euint8 partRight = TFHE.and(TFHE.rotr(a, delta), deltamask);
        euint8 partLeft = TFHE.and(TFHE.rotl(a, delta), TFHE.rotr(deltamask, delta));

        return TFHE.or(partLeft, partRight);
    }
}
