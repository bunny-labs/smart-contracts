// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Clonable} from "bunny-libs/Clonable/Clonable.sol";
import {MembershipToken} from "bunny-libs/MembershipToken/MembershipToken.sol";

contract Distributor is MembershipToken, Clonable {
    //********//
    // Types //
    //*******//

    error FailedTransfer(address to);
    error FailedRefund(address to);

    event Deposited(address from, uint256 amount);
    event Distributed();

    struct Outflow {
        address destination;
        uint256 amount;
    }

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
     * Distribute the full balance of an ERC20 token at an address to members.
     * @dev Needs token approval. Capped to uint224 at a time to avoid overflow.
     * @param asset The token that should be distributed.
     * @param source The address that we should distribute from.
     */
    function distribute(address asset, address source) external memberOnly {
        IERC20 token = IERC20(asset);
        Outflow[] memory outflows = _generateOutflows(token.balanceOf(source));

        for (uint256 i = 0; i < outflows.length; i++) {
            Outflow memory outflow = outflows[i];

            bool success = token.transferFrom(source, outflow.destination, outflow.amount);
            if (!success) revert FailedTransfer(outflow.destination);
        }

        emit Distributed();
    }

    /**
     * Distribute the full balance of an ERC20 token held by this contract to members.
     * @param asset The token that should be distributed.
     */
    function distribute(address asset) external memberOnly {
        IERC20 token = IERC20(asset);
        Outflow[] memory outflows = _generateOutflows(token.balanceOf(address(this)));

        for (uint256 i = 0; i < outflows.length; i++) {
            Outflow memory outflow = outflows[i];

            bool success = token.transfer(outflow.destination, outflow.amount);
            if (!success) revert FailedTransfer(outflow.destination);
        }

        emit Distributed();
    }

    /**
     * Distribute the full base token balance of this contract to members.
     * @dev Payable so the base token can be supplied when called.
     */
    function distribute() external payable memberOnly {
        Outflow[] memory outflows = _generateOutflows(address(this).balance);

        for (uint256 i = 0; i < outflows.length; i++) {
            Outflow memory outflow = outflows[i];

            (bool success,) = outflow.destination.call{value: outflow.amount}("");
            if (!success) revert FailedTransfer(outflow.destination);
        }

        emit Distributed();
    }

    //*************//
    // Simulations //
    //*************//

    /**
     * Simulate the distribution of an ERC20 token from a source address.
     * @param asset The address of the token that will be distributed.
     * @param source The address that holds the tokens that should be distributed.
     */
    function simulate(address asset, address source) external view returns (Outflow[] memory) {
        return _generateOutflows(IERC20(asset).balanceOf(source));
    }

    /**
     * Simulate the distribution of an ERC20 token from this contract.
     * @param asset The address of the token that will be distributed.
     */
    function simulate(address asset) external view returns (Outflow[] memory) {
        return _generateOutflows(IERC20(asset).balanceOf(address(this)));
    }

    /**
     * Simulate the distribution of this contract's balance.
     */
    function simulate() external view returns (Outflow[] memory) {
        return _generateOutflows(address(this).balance);
    }

    /**
     * Simulate the distribution of an arbitrary amount.
     * @param amount The amount to be distributed.
     */
    function simulate(uint256 amount) external view returns (Outflow[] memory) {
        return _generateOutflows(amount);
    }

    //***********//
    // Internals //
    //***********//

    /**
     * Generate outflows based on current membership distribution and an amount of tokens.
     * @param totalTokens The total amount of tokens that should be distributed.
     */
    function _generateOutflows(uint256 totalTokens) internal view returns (Outflow[] memory) {
        uint256 totalMemberships = totalSupply;
        Outflow[] memory outflows = new Outflow[](totalMemberships);

        uint224 distributionAmount =
            totalTokens <= MAX_DISTRIBUTION_AMOUNT ? uint224(totalTokens) : MAX_DISTRIBUTION_AMOUNT;

        for (uint256 tokenId = 0; tokenId < totalMemberships; tokenId++) {
            outflows[tokenId].destination = ownerOf(tokenId);
            outflows[tokenId].amount = tokenShare(tokenId, distributionAmount);
        }

        return outflows;
    }

    /**
     * Fallback function to support direct payments to the contract address.
     */
    fallback() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
