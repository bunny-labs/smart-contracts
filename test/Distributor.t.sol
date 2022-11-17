// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/utils/Strings.sol";

import "../src/Distributor/Distributor.sol";
import "./Utils.sol";

contract DistributorTest is Test {
    TestToken token;

    function setUp() public virtual {
        token = new TestToken();
    }

    function setupMembers(uint8 memberCount, uint16 sharesSeed)
        public
        returns (Distributor.Member[] memory)
    {
        Distributor.Member[] memory members = new Distributor.Member[](
            memberCount
        );
        uint16[] memory shares = Utils.expand16(sharesSeed, memberCount);

        for (uint8 i; i < memberCount; i++) {
            members[i] = Distributor.Member(
                makeAddr(Strings.toString(uint256(i))),
                shares[i]
            );
        }

        return members;
    }
}

contract DistributorInitializationTest is DistributorTest {
    function setUp() public override {
        DistributorTest.setUp();
    }

    function testCanInitialize() public {
        new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(42, 69)
            })
        );
    }

    function testCanInitializeERC721(string memory name, string memory symbol)
        public
    {
        Distributor d = new Distributor(
            Distributor.Configuration({
                name: name,
                symbol: symbol,
                token: address(token),
                members: setupMembers(42, 69)
            })
        );

        assertEq(d.name(), name);
        assertEq(d.symbol(), symbol);
    }

    function testCanInitializeTokenAddress(address testToken) public {
        Distributor d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: testToken,
                members: setupMembers(42, 69)
            })
        );

        assertEq(address(d.asset()), testToken);
    }

    function testCannotInitializeWithNoMembers() public {
        Distributor.Member[] memory members;

        vm.expectRevert(Distributor.NoMembers.selector);
        Distributor d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: members
            })
        );
    }

    function testCanInitializeTotalShares(uint8 memberCount, uint16 sharesSeed)
        public
    {
        vm.assume(memberCount > 0);

        Distributor.Member[] memory members = setupMembers(
            memberCount,
            sharesSeed
        );

        Distributor d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: members
            })
        );

        uint32 totalShares;
        for (uint32 i; i < memberCount; i++) {
            totalShares += members[i].shares;
        }
        assertEq(d.totalShares(), totalShares);
    }

    function testCanInitializeMemberShares(uint8 memberCount, uint16 sharesSeed)
        public
    {
        vm.assume(memberCount > 0);

        Distributor.Member[] memory members = setupMembers(
            memberCount,
            sharesSeed
        );

        Distributor d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: members
            })
        );

        for (uint8 i; i < memberCount; i++) {
            assertEq(d.memberShares(i), members[i].shares);
        }
    }

    function testCanInitializeMemberCount(uint8 memberCount) public {
        vm.assume(memberCount > 0);

        Distributor d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(memberCount, 420)
            })
        );

        assertEq(d.totalMembers(), memberCount);
    }

    function testCanMintMemberTokens(uint8 memberCount, uint16 sharesSeed)
        public
    {
        vm.assume(memberCount > 0);

        Distributor.Member[] memory members = setupMembers(
            memberCount,
            sharesSeed
        );

        Distributor d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: members
            })
        );

        for (uint8 i; i < memberCount; i++) {
            assertEq(d.ownerOf(i), members[i].wallet);
        }
    }
}

contract DistributorDepositTest is DistributorTest {
    address treasury;
    address member;

    Distributor d;

    function setUp() public override {
        DistributorTest.setUp();

        treasury = makeAddr("treasury");
        member = makeAddr("0");

        d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(42, 69)
            })
        );
    }

    function testCanDeposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint224).max);

        token.mint(treasury, amount);

        vm.prank(treasury);
        token.approve(address(d), type(uint256).max);

        vm.prank(member);
        d.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(d)), amount);
        assertEq(d.totalDeposited(), amount);
    }

    function testCannotDepositIfNotAMember() public {}

    function testCannotDepositFromEmptyAddress() public {
        vm.expectRevert(Distributor.NothingToDeposit.selector);
        vm.prank(member);
        d.deposit(treasury);
    }

    function testCannotDepositWithoutApproval() public {
        token.mint(treasury, 420);

        vm.expectRevert();
        vm.prank(member);
        d.deposit(treasury);
    }

    function testCanRegisterDepositedTokens(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint224).max);

        token.mint(treasury, amount);

        vm.prank(treasury);
        token.approve(address(d), type(uint256).max);

        vm.prank(member);
        d.deposit(treasury);
    }
}

contract DistributorClaimTest is DistributorTest {
    address treasury;
    address member;

    Distributor d;

    function setUp() public override {
        DistributorTest.setUp();

        treasury = makeAddr("treasury");
        member = makeAddr("0");

        d = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(42, 69)
            })
        );

        vm.prank(treasury);
        token.approve(address(d), type(uint256).max);
    }

    function testCanClaimTokens(uint256 tokenAmount) public {
        uint8 memberCount = d.totalMembers();
        vm.assume(tokenAmount >= memberCount);
        vm.assume(tokenAmount < type(uint224).max);

        token.mint(treasury, tokenAmount);
        vm.prank(member);
        d.deposit(treasury);

        for (uint8 i; i < memberCount; i++) {
            address memberAddress = makeAddr(Strings.toString(i));
            vm.prank(memberAddress);
            d.claim(i);
        }

        // Only dust is left
        assertTrue(token.balanceOf(address(d)) < memberCount);
    }

    function testCannotClaimIfNotAMember() public {}
}
