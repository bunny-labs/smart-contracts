// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {MembershipToken} from "../MembershipToken/MembershipToken.sol";

contract PullDistributor is MembershipToken {
    /*********
     * Types *
     *********/

    struct Configuration {
        string name;
        string symbol;
        string imageURI;
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

    /// Maximum amount of tokens that can be deposited in this contract.
    /// @dev The limit exists so that maximum shares per member (uint16) * maximum deposit (uint240) would never overflow.
    uint256 public constant MAXIMUM_DEPOSIT = type(uint240).max;

    /// The underlying ERC20 asset that is distributed to members
    IERC20Metadata public asset;

    /// The total amount of underlying asset that has been deposited
    uint256 public totalDeposited;
    /// The total amount of underlying asset that has been claimed
    uint256 public totalClaimed;
    /// Mapping to track the amount of underlying asset claimed by each member
    mapping(uint256 => uint256) public memberClaimed;

    /// URI of the image asset to use in NFT metadata
    string public imageURI;

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
        uint256 balance = asset.balanceOf(treasury);

        if (balance == 0) revert NothingToDeposit();
        if (balance > MAXIMUM_DEPOSIT) revert TooLargeDeposit();

        bool success = asset.transferFrom(treasury, address(this), balance);
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
     * Claim all available tokens for the specified member.
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
    function unregisteredTokens() public view returns (uint256) {
        return asset.balanceOf(address(this)) + totalClaimed - totalDeposited;
    }

    /**
     * Get the number of tokens that are currently claimable for a member
     */
    function claimableTokens(uint256 membershipTokenId)
        public
        view
        returns (uint256)
    {
        uint224 total = totalDeposited > type(uint224).max
            ? type(uint224).max
            : uint224(totalDeposited);

        uint256 memberTokens = tokenShare(membershipTokenId, total);
        uint256 claimedTokens = memberClaimed[membershipTokenId];

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
        imageURI = config.imageURI;
        asset = IERC20Metadata(config.token);

        MembershipToken._initialize(config.name, config.symbol, config.members);
    }

    /**
     * @dev Register any unaccounted tokens of the underlying asset
     */
    function _registerTokens() internal {
        uint256 tokenAmount = unregisteredTokens();
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
        uint256 claimAmount = claimableTokens(membershipTokenId);

        memberClaimed[membershipTokenId] += claimAmount;
        totalClaimed += claimAmount;
        emit Claim(membershipTokenId, claimAmount);

        bool success = asset.transfer(ownerOf(membershipTokenId), claimAmount);
        if (!success) revert FailedTransfer();
    }
}
