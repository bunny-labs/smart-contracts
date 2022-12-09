// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {Base64} from "./Base64.sol";

abstract contract MembershipToken is ERC721("", "") {
    /*********
     * Types *
     *********/

    struct Membership {
        address wallet;
        uint32 weight;
    }

    error NotAMember();
    error TokenDoesNotExist();

    /*************
     * Variables *
     *************/

    /// The total supply of membership tokens
    uint16 public totalSupply;

    /// Mapping to track weights per individual membership
    mapping(uint256 => uint32) public membershipWeight;

    /// The total number of weights across all tokens
    uint48 public totalWeights;

    /******************
     * Public functions
     ******************/

    /**
     * Get a token's proportional share of a specified total value.
     * @param tokenId ID of the membership token.
     * @param value The value we need to get a proportional share from.
     */
    function tokenShare(uint256 tokenId, uint224 value)
        public
        view
        returns (uint256)
    {
        return (uint256(value) * membershipWeight[tokenId]) / totalWeights;
    }

    /**
     * Get metadata for the membership token.
     * @param tokenId ID of the membership token.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (tokenId >= totalSupply) revert TokenDoesNotExist();

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        name,
                        " #",
                        Strings.toString(tokenId),
                        '","image":"","attributes":[{"trait_type":"Shares","value":',
                        Strings.toString(membershipWeight[tokenId]),
                        ',"max_value":',
                        Strings.toString(totalWeights),
                        "}]}"
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    /*************
     * Internals *
     *************/

    /**
     * @dev Initialize the contract.
     * @param name_ Membership token name.
     * @param symbol_ Membership token symbol.
     * @param memberships Memberships to mint on initialization.
     */
    function _initialize(
        string memory name_,
        string memory symbol_,
        Membership[] memory memberships
    ) internal {
        name = name_;
        symbol = symbol_;
        _mintMemberships(memberships);
    }

    /**
     * @dev Mint a new membership token.
     * @param membership Information for the membership.
     */
    function _mintMembership(Membership memory membership) internal {
        uint256 tokenId = totalSupply;

        totalSupply += 1;
        totalWeights += membership.weight;
        membershipWeight[tokenId] = membership.weight;

        _mint(membership.wallet, tokenId);
    }

    /**
     * @dev Mint a batch of membership tokens.
     * @param memberships List of new memberships to mint.
     */
    function _mintMemberships(Membership[] memory memberships) internal {
        uint256 membershipCount = memberships.length;

        for (uint256 i = 0; i < membershipCount; i++) {
            _mintMembership(memberships[i]);
        }
    }

    /**
     * @dev Restrict function to be called by members only.
     */
    modifier memberOnly() {
        if (balanceOf(msg.sender) == 0) revert NotAMember();
        _;
    }
}
