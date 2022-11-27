// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract Distributor is ERC721 {
    /***********
     * Structs *
     ***********/

    struct Member {
        address wallet;
        uint16 shares;
    }

    struct Configuration {
        string name;
        string symbol;
        address token;
        Member[] members;
    }

    /**********
     * Errors *
     **********/

    error NoMembers();
    error NothingToDeposit();
    error TooLargeDeposit();
    error NotAMember();
    error NotYourToken();

    /*************
     * Constants *
     *************/

    /// Contract code version
    uint256 public constant CODE_VERSION = 1;

    /********************
     * Public variables *
     ********************/

    /// The underlying ERC20 asset that is distributed to members
    IERC20 public asset;

    /// The total number of members
    uint8 public totalMembers;
    /// The total number of shares across all members
    uint32 public totalShares;
    /// Mapping to track shares per member
    mapping(uint8 => uint16) public memberShares;

    /// The total amount of underlying asset that has been deposited
    uint256 public totalDeposited;
    /// The total amount of underlying asset that has been claimed
    uint256 public totalClaimed;
    /// Mapping to track the amount of underlying asset claimed by each member
    mapping(uint8 => uint256) public memberClaimed;

    /******************
     * Initialization *
     ******************/

    constructor(Configuration memory config) ERC721("", "") {
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
    function deposit(address treasury) external {
        if (balanceOf(msg.sender) == 0) revert NotAMember();

        uint256 balance = asset.balanceOf(treasury);

        if (balance == 0) revert NothingToDeposit();
        if (balance > type(uint240).max) revert TooLargeDeposit();

        asset.transferFrom(treasury, address(this), balance);
        _registerDeposit();
    }

    /**
     * Claim all available tokens for the specified member
     * @dev Callable by the owner of the membership token only.
     * @param membershipTokenId The ID of the membership token used for claiming.
     */
    function claim(uint8 membershipTokenId) external {
        _claim(membershipTokenId);
    }

    /******************
     * View functions *
     ******************/

    function tokenURI(uint256 membershipTokenId)
        public
        view
        override
        returns (string memory)
    {
        return "";
    }

    /*************
     * Internals *
     *************/

    /**
     * @dev Initialize contract.
     * @param config Configuration struct to use for initialization.
     */
    function _initialize(Configuration memory config) internal {
        name = config.name;
        symbol = config.symbol;

        asset = IERC20(config.token);
        _importMembers(config.members);
    }

    /**
     * @dev Import members into the contract.
     * @param newMembers List of new members to add.
     */
    function _importMembers(Member[] memory newMembers) internal {
        uint8 newMemberCount = uint8(newMembers.length);
        if (newMemberCount == 0) revert NoMembers();

        for (uint8 i; i < newMemberCount; i++) {
            _importMember(newMembers[i]);
        }
    }

    /**
     * @dev Import a single member into the contract
     * @param newMember Member details for the new member
     */
    function _importMember(Member memory newMember) internal {
        uint8 membershipTokenId = totalMembers;

        totalMembers += 1;
        totalShares += newMember.shares;
        memberShares[membershipTokenId] = newMember.shares;

        _mint(newMember.wallet, membershipTokenId);
    }

    /**
     * @dev Register a new deposit of the underlying asset
     */
    function _registerDeposit() internal {
        uint256 unregisteredTokens = asset.balanceOf(address(this)) +
            totalClaimed -
            totalDeposited;

        totalDeposited += unregisteredTokens;
    }

    /**
     * @dev Claim all available tokens of the underlying asset that are available to the specified member.
     * @param membershipTokenId ID of the membership token we're claiming for.
     */
    function _claim(uint8 membershipTokenId) internal {
        if (msg.sender != ownerOf(membershipTokenId)) revert NotYourToken();

        uint16 shares = memberShares[membershipTokenId];
        uint256 memberTokens = (totalDeposited * uint256(shares)) /
            uint256(totalShares);
        uint256 claimedTokens = memberClaimed[membershipTokenId];
        uint256 claimableTokens = memberTokens - claimedTokens;

        memberClaimed[membershipTokenId] += claimableTokens;
        totalClaimed += claimableTokens;
        asset.transfer(ownerOf(membershipTokenId), claimableTokens);
    }
}
