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
        Distributor distributor = new Distributor(
            Distributor.Configuration({
                name: name,
                symbol: symbol,
                token: address(token),
                members: setupMembers(42, 69)
            })
        );

        assertEq(distributor.name(), name);
        assertEq(distributor.symbol(), symbol);
    }

    function testCanInitializeTokenAddress(address testToken) public {
        Distributor distributor = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: testToken,
                members: setupMembers(42, 69)
            })
        );

        assertEq(address(distributor.asset()), testToken);
    }

    function testCanInitializeWithMaximumMembers() public {
        new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(type(uint8).max, 69)
            })
        );
    }

    function testCannotInitializeWithNoMembers() public {
        Distributor.Member[] memory members;

        vm.expectRevert(Distributor.NoMembers.selector);
        new Distributor(
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
            assertEq(d.balanceOf(d.ownerOf(i)), 1);
        }
    }
}

contract DistributorDepositTest is DistributorTest {
    address treasury;
    address firstMember;

    Distributor distributor;

    function setUp() public override {
        DistributorTest.setUp();

        treasury = makeAddr("treasury");
        firstMember = makeAddr("0");

        distributor = new Distributor(
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
        vm.assume(amount < type(uint240).max);

        token.mint(treasury, amount);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(distributor.totalDeposited(), amount);
    }

    function testCanDepositByAnyMember(uint232 amount) public {
        vm.assume(amount > 0);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        uint8 totalMembers = distributor.totalMembers();
        for (uint8 i; i < totalMembers; i++) {
            address member = makeAddr(Strings.toString(i));
            token.mint(treasury, amount);
            vm.prank(member);
            distributor.deposit(treasury);
        }
    }

    function testCanDepositMaxAmount() public {
        uint256 amount = type(uint240).max;

        token.mint(treasury, amount);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(distributor.totalDeposited(), amount);
    }

    function testCannotDepositTooMuch() public {
        uint256 amount = uint256(type(uint240).max) + 1;
        token.mint(treasury, amount);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        vm.expectRevert(Distributor.TooLargeDeposit.selector);
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCannotDepositIfNotAMember() public {
        address nonMember = makeAddr("NotAMember");

        token.mint(treasury, 420);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        vm.expectRevert(Distributor.NotAMember.selector);
        vm.prank(nonMember);
        distributor.deposit(treasury);
    }

    function testCannotDepositFromEmptyAddress() public {
        vm.expectRevert(Distributor.NothingToDeposit.selector);
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCannotDepositWithoutApproval() public {
        token.mint(treasury, 420);

        vm.expectRevert();
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCanRegisterDepositedTokens(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint240).max);

        token.mint(treasury, amount);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCanRegisterMaxDeposit() public {
        token.mint(treasury, type(uint240).max);

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);

        vm.prank(firstMember);
        distributor.deposit(treasury);
    }
}

contract DistributorClaimTest is DistributorTest {
    address treasury;
    address member;

    Distributor distributor;

    function setUp() public override {
        DistributorTest.setUp();

        treasury = makeAddr("treasury");
        member = makeAddr("0");

        distributor = new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(42, 69)
            })
        );

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);
    }

    function testCanClaimTokens(uint256 tokenAmount) public {
        uint8 memberCount = distributor.totalMembers();
        vm.assume(tokenAmount >= memberCount);
        vm.assume(tokenAmount < type(uint240).max);

        token.mint(treasury, tokenAmount);
        vm.prank(member);
        distributor.deposit(treasury);

        for (uint8 i; i < memberCount; i++) {
            address memberAddress = makeAddr(Strings.toString(i));
            vm.prank(memberAddress);
            distributor.claim(i);
        }

        // Only dust is left
        assertTrue(token.balanceOf(address(distributor)) < memberCount);
    }

    function testCannotClaimIfNotAMember() public {
        token.mint(treasury, 420);
        vm.prank(member);
        distributor.deposit(treasury);

        address nonMember = makeAddr("NotAMember");
        vm.expectRevert(Distributor.NotYourToken.selector);
        vm.prank(nonMember);
        distributor.claim(0);
    }

    function testCannotClaimIfNotYourToken(uint256 tokenAmount) public {
        uint8 memberCount = distributor.totalMembers();
        vm.assume(tokenAmount >= memberCount);
        vm.assume(tokenAmount < type(uint240).max);

        token.mint(treasury, tokenAmount);
        vm.prank(member);
        distributor.deposit(treasury);

        for (uint8 i; i < memberCount; i++) {
            address memberAddress = makeAddr(
                Strings.toString((i + 1) % memberCount)
            );
            vm.expectRevert(Distributor.NotYourToken.selector);
            vm.prank(memberAddress);
            distributor.claim(i);
        }
    }
}

contract DistributorRealWorldTest is Test {}
