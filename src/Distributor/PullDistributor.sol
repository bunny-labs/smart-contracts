// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {MembershipToken} from "../MembershipToken/MembershipToken.sol";

contract PullDistributor is MembershipToken {
    /*********
     * Types *
     *********/

    struct Configuration {
        string name;
        string symbol;
        address token;
        Membership[] members;
    }

    error NothingToDeposit();
    error NothingToRegister();
    error TooLargeDeposit();
    error NotYourToken();
    error FailedTransfer();

    event Deposit(uint256 amount);
    event Claim(uint256 membershipTokenId, uint256 amount);

    /*************
     * Variables *
     *************/

    /// Contract version
    uint256 public constant CONTRACT_VERSION = 1_00;

    /// The underlying ERC20 asset that is distributed to members
    IERC20 public token;

    /// The total amount of underlying asset that has been deposited
    uint224 public totalDeposited;
    /// The total amount of underlying asset that has been claimed
    uint224 public totalClaimed;
    /// Mapping to track the amount of underlying asset claimed by each member
    mapping(uint256 => uint224) public memberClaimed;

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
     * Transfer all tokens of the underlying asset from another address to this contract and register the transferred amount.
     * @dev Treasury address must approve this contract before deposit() can be called. Callable by any member.
     * @param treasury Address the funds will be pulled from.
     */
    function deposit(address treasury) external memberOnly {
        uint256 balance = token.balanceOf(treasury);

        if (balance == 0) revert NothingToDeposit();
        if (balance + totalDeposited > type(uint224).max) {
            revert TooLargeDeposit();
        }

        bool success = token.transferFrom(treasury, address(this), balance);
        if (!success) revert FailedTransfer();

        _registerTokens();
    }

    /**
     * Register all unaccounted tokens held by the contract.
     * @dev This enables a workflow that doesn't require token approvals. Asset can be transferred to this contract and any member can call register() to prepare the tokens for claiming.
     */
    function register() external memberOnly {
        _registerTokens();
    }

    /**
     * Claim all available tokens for the specified membership token.
     * @dev Callable only by the owner of the membership token.
     * @param membershipTokenId The ID of the membership token used for claiming.
     */
    function claim(uint256 membershipTokenId) external {
        _claim(membershipTokenId);
    }

    /**
     * Claim all available tokens for multiple membership tokens.
     * @dev Use this if you own multiple membership tokens.
     * @param membershipTokenIds The IDs of the membership tokens used for claiming.
     */
    function claim(uint256[] calldata membershipTokenIds) external {
        for (uint256 i = 0; i < membershipTokenIds.length; i++) {
            _claim(i);
        }
    }

    /******************
     * View functions *
     ******************/

    /**
     * Get the amount of unregistered tokens of the underlying asset that are held by this contract.
     */
    function unregisteredTokens() public view returns (uint224) {
        return
            uint224(token.balanceOf(address(this))) +
            totalClaimed -
            totalDeposited;
    }

    /**
     * Get the number of tokens that are currently claimable for a member
     */
    function claimableTokens(uint256 membershipTokenId)
        public
        view
        returns (uint224)
    {
        uint224 memberTokens = tokenShare(membershipTokenId, totalDeposited);
        uint224 claimedTokens = memberClaimed[membershipTokenId];

        return memberTokens - claimedTokens;
    }

    /*************
     * Internals *
     *************/

    /**
     * @dev Initialize contract.
     * @param config Configuration struct to use for initialization.
     */
    function _initialize(Configuration memory config) internal {
        token = IERC20(config.token);
        MembershipToken._initialize(config.name, config.symbol, config.members);
    }

    /**
     * @dev Register any unaccounted tokens of the underlying asset
     */
    function _registerTokens() internal {
        uint224 tokenAmount = unregisteredTokens();
        if (tokenAmount == 0) revert NothingToRegister();

        totalDeposited += tokenAmount;
        emit Deposit(tokenAmount);
    }

    /**
     * @dev Claim all available tokens of the underlying asset that are available to the specified member.
     * @param membershipTokenId ID of the membership token we're claiming for.
     */
    function _claim(uint256 membershipTokenId) internal {
        if (msg.sender != ownerOf(membershipTokenId)) revert NotYourToken();
        uint224 claimAmount = claimableTokens(membershipTokenId);

        memberClaimed[membershipTokenId] += claimAmount;
        totalClaimed += claimAmount;
        emit Claim(membershipTokenId, claimAmount);

        bool success = token.transfer(ownerOf(membershipTokenId), claimAmount);
        if (!success) revert FailedTransfer();
    }
}
