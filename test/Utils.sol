// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "solmate/tokens/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TEST", 18) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

library Utils {
    function expand8(uint8 seed, uint256 size)
        public
        pure
        returns (uint8[] memory)
    {
        uint8[] memory numbers = new uint8[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint8(
                uint256(keccak256(abi.encodePacked(seed, i))) % type(uint8).max
            );
        }
        return numbers;
    }

    function expand16(uint16 seed, uint256 size)
        public
        pure
        returns (uint16[] memory)
    {
        uint16[] memory numbers = new uint16[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint16(
                uint256(keccak256(abi.encodePacked(seed, i))) % type(uint16).max
            );
        }
        return numbers;
    }

    function expand32(uint32 seed, uint256 size)
        public
        pure
        returns (uint32[] memory)
    {
        uint32[] memory numbers = new uint32[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint32(
                uint256(keccak256(abi.encodePacked(seed, i))) % type(uint32).max
            );
        }
        return numbers;
    }

    function expand64(uint64 seed, uint256 size)
        public
        pure
        returns (uint64[] memory)
    {
        uint64[] memory numbers = new uint64[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint64(
                uint256(keccak256(abi.encodePacked(seed, i))) % type(uint64).max
            );
        }
        return numbers;
    }

    function expand128(uint128 seed, uint256 size)
        public
        pure
        returns (uint128[] memory)
    {
        uint128[] memory numbers = new uint128[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint128(
                uint256(keccak256(abi.encodePacked(seed, i))) %
                    type(uint128).max
            );
        }
        return numbers;
    }

    function expand248(uint248 seed, uint256 size)
        public
        pure
        returns (uint248[] memory)
    {
        uint248[] memory numbers = new uint248[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint248(
                uint256(keccak256(abi.encodePacked(seed, i))) %
                    type(uint248).max
            );
        }
        return numbers;
    }

    function expand256(uint256 seed, uint256 size)
        public
        pure
        returns (uint256[] memory)
    {
        uint256[] memory numbers = new uint256[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint256(keccak256(abi.encodePacked(seed, i)));
        }
        return numbers;
    }
}
