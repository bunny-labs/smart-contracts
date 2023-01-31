// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Clonable} from "bunny-libs/Clonable/Clonable.sol";
import {MembershipToken} from "bunny-libs/MembershipToken/MembershipToken.sol";

contract Distributor is MembershipToken, Clonable {
    //********//
    // Types //
    //*******//

    error FailedTransfer();

    event Distributed();

    //***********//
    // Variables //
    //***********//

    /// Contract version
    uint256 public constant CONTRACT_VERSION = 2_00;

    /// Maximum token amount that can be distributed at once.
    /// This is to avoid overflows when calculating member shares.
    uint224 constant MAX_DISTRIBUTION_AMOUNT = type(uint224).max;

    //****************//
    // Initialization //
    //****************//

    constructor(
        string memory name_,
        string memory symbol_,
        Membership[] memory members_,
        CloningConfig memory cloningConfig
    ) initializer Clonable(cloningConfig) {
        _initialize(encodeInitdata(name_, symbol_, members_));
    }

    /**
     * Initialize the contract.
     * @param initdata Contract initialization data, encoded as bytes.
     */
    function _initialize(bytes memory initdata) internal override {
        (string memory name_, string memory symbol_, Membership[] memory members_) = decodeInitdata(initdata);
        MembershipToken._initialize(name_, symbol_, members_);
    }

    /**
     * Helper for encoding initialization parameters to bytes.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param members_ Memberships to mint.
     */
    function encodeInitdata(string memory name_, string memory symbol_, Membership[] memory members_)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(name_, symbol_, members_);
    }

    /**
     * Helper for decoding initialization parameters from bytes.
     * @param initdata nitialization data, encoded to bytes.
     */
    function decodeInitdata(bytes memory initdata)
        public
        pure
        returns (string memory, string memory, Membership[] memory)
    {
        return abi.decode(initdata, (string, string, Membership[]));
    }

    //****************//
    // Member actions //
    //****************//

    /**
     * Distribute the full balance of a token at an address to members.
     * @dev Needs token approval. Capped to uint224 at a time to avoid overflow.
     * @param asset The ERC20 token that should be distributed.
     * @param source The address that we should distribute from.
     */
    function distribute(address asset, address source) external memberOnly {
        IERC20 token = IERC20(asset);

        uint256 tokenBalance = token.balanceOf(source);
        uint224 distributionAmount =
            tokenBalance <= MAX_DISTRIBUTION_AMOUNT ? uint224(tokenBalance) : MAX_DISTRIBUTION_AMOUNT;

        uint256 totalMemberships = totalSupply;
        for (uint256 tokenId = 0; tokenId < totalMemberships; tokenId++) {
            address member = ownerOf(tokenId);
            uint256 tokens = tokenShare(tokenId, distributionAmount);

            bool success = token.transferFrom(source, member, tokens);
            if (!success) revert FailedTransfer();
        }

        emit Distributed();
    }
}
