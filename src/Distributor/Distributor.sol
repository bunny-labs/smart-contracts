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

    error NothingToDeposit();
    error NoMembers();
    error NotAMember();

    /*************
     * Constants *
     *************/

    /********************
     * Public variables *
     ********************/

    IERC20 public asset;

    uint8 public totalMembers;
    uint32 public totalShares;
    mapping(uint8 => uint16) public memberShares;

    uint256 public totalDeposited;
    uint256 public totalClaimed;
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

    function deposit(address from) external memberOnly {
        uint256 balance = asset.balanceOf(from);

        if (balance == 0) revert NothingToDeposit();

        asset.transferFrom(from, address(this), balance);
        _registerDeposit();
    }

    function claim(uint8 memberId) external memberOnly {
        uint64 shares = memberShares[memberId];
        uint256 memberTokens = (totalDeposited * uint256(shares)) /
            uint256(totalShares);
        uint256 claimedTokens = memberClaimed[memberId];
        uint256 claimableTokens = memberTokens - claimedTokens;

        memberClaimed[memberId] += claimableTokens;
        totalClaimed += claimableTokens;
        asset.transfer(ownerOf(memberId), claimableTokens);
    }

    /******************
     * View functions *
     ******************/

    function tokenURI(uint256 memberId)
        public
        view
        override
        returns (string memory)
    {
        return "";
    }

    /*************
     * Modifiers *
     *************/

    modifier memberOnly() {
        require(balanceOf(msg.sender) > 0, "Not a member");
        _;
    }

    /*************
     * Internals *
     *************/

    function _initialize(Configuration memory config) internal {
        name = config.name;
        symbol = config.symbol;

        asset = IERC20(config.token);
        _importMembers(config.members);
    }

    function _importMembers(Member[] memory newMembers) internal {
        uint8 newMemberCount = uint8(newMembers.length);
        if (newMemberCount == 0) revert NoMembers();

        for (uint8 i; i < newMemberCount; i++) {
            _importMember(newMembers[i]);
        }
    }

    function _importMember(Member memory newMember) internal {
        uint8 memberId = totalMembers;

        totalMembers += 1;
        totalShares += newMember.shares;
        memberShares[memberId] = newMember.shares;

        _mint(newMember.wallet, memberId);
    }

    function _registerDeposit() internal {
        uint256 unregisteredTokens = asset.balanceOf(address(this)) +
            totalClaimed -
            totalDeposited;

        totalDeposited += unregisteredTokens;
        require(totalDeposited < type(uint224).max, "Too many deposits");
    }
}
