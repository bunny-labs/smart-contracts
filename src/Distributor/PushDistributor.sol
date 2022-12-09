// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {MembershipToken} from "../MembershipToken/MembershipToken.sol";

contract PushDistributor is MembershipToken {
    /*********
     * Types *
     *********/

    struct Configuration {
        string name;
        string symbol;
        Membership[] members;
    }

    error FailedTransfer();

    event Distributed();

    /*************
     * Variables *
     *************/

    /// Contract version
    uint256 public constant CONTRACT_VERSION = 1_00;

    /// Maximum token amount that can be distributed at once.
    /// This is to avoid overflows when calculating member shares.
    uint224 constant MAX_DISTRIBUTION_AMOUNT = type(uint224).max;

    /******************
     * Initialization *
     ******************/

    constructor(Configuration memory config) {
        _initialize(config);
    }

    /******************
     * Member actions *
     ******************/

    /**
     * Distribute the full balance of a token at an address to members.
     * @dev Needs token approval. Capped to uint224 at a time to avoid overflow.
     * @param asset The ERC20 token that should be distributed.
     * @param source The address that we should distribute from.
     */
    function distribute(address asset, address source) external memberOnly {
        IERC20 token = IERC20(asset);

        uint256 tokenBalance = token.balanceOf(source);
        uint224 distributionAmount = tokenBalance <= MAX_DISTRIBUTION_AMOUNT
            ? uint224(tokenBalance)
            : MAX_DISTRIBUTION_AMOUNT;

        _distribute(asset, source, distributionAmount);
    }

    /*************
     * Internals *
     *************/

    /**
     * @dev Internal function to calculate shares and perform distribution.
     * @param asset The ERC20 token that should be distributed.
     * @param source The address that we should distribute from.
     * @param amount The full amount that should be distributed.
     */
    function _distribute(
        address asset,
        address source,
        uint224 amount
    ) internal {
        IERC20 token = IERC20(asset);

        uint256 totalMemberships = totalSupply;
        for (uint256 tokenId = 0; tokenId < totalMemberships; tokenId++) {
            address member = ownerOf(tokenId);
            uint256 tokens = tokenShare(tokenId, amount);

            bool success = token.transferFrom(source, member, tokens);
            if (!success) revert FailedTransfer();
        }

        emit Distributed();
    }

    /**
     * @dev Initialize contract.
     * @param config Configuration struct to use for initialization.
     */
    function _initialize(Configuration memory config) internal {
        MembershipToken._initialize(config.name, config.symbol, config.members);
    }
}
