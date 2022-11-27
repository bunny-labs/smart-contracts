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

    function setupMaximumMembers()
        public
        returns (Distributor.Member[] memory)
    {
        uint8 memberCount = type(uint8).max;
        Distributor.Member[] memory members = new Distributor.Member[](
            memberCount
        );

        for (uint8 i; i < memberCount; i++) {
            members[i] = Distributor.Member(
                makeAddr(Strings.toString(uint256(i))),
                type(uint16).max
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

    function testCanInitializeAssetAddress(address testToken) public {
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

    function testCanInitializeWithMaximumMembersAndShares() public {
        new Distributor(
            Distributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMaximumMembers()
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

    function testCanMintMembershipTokens(uint8 memberCount, uint16 sharesSeed)
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

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);
    }

    function testCanDeposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < distributor.MAXIMUM_DEPOSIT());

        token.mint(treasury, amount);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(distributor.totalDeposited(), amount);
    }

    function testCanDepositByAnyMember(uint232 amount) public {
        vm.assume(amount > 0);

        uint8 totalMembers = distributor.totalMembers();
        for (uint8 i; i < totalMembers; i++) {
            address member = makeAddr(Strings.toString(i));
            token.mint(treasury, amount);
            vm.prank(member);
            distributor.deposit(treasury);
        }

        assertEq(
            distributor.totalDeposited(),
            uint256(amount) * uint256(totalMembers)
        );
    }

    function testCanDepositMaxAmount() public {
        uint256 amount = distributor.MAXIMUM_DEPOSIT();

        token.mint(treasury, amount);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(distributor.totalDeposited(), amount);
    }

    function testCannotDepositOverMaxAmount() public {
        uint256 amount = uint256(distributor.MAXIMUM_DEPOSIT()) + 1;
        token.mint(treasury, amount);

        vm.expectRevert(Distributor.TooLargeDeposit.selector);
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCannotDepositIfNotAMember() public {
        address nonMember = makeAddr("NotAMember");

        token.mint(treasury, 420);

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
        vm.prank(treasury);
        token.approve(address(distributor), 0);

        vm.expectRevert();
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCanTransferAssetWhenDepositing(uint256 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount < distributor.MAXIMUM_DEPOSIT());

        token.mint(treasury, depositAmount);

        assertEq(token.balanceOf(treasury), depositAmount);
        assertEq(token.balanceOf(address(distributor)), 0);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), depositAmount);
    }

    function testCanRegisterDepositedTokens(uint256 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount < distributor.MAXIMUM_DEPOSIT());

        token.mint(treasury, depositAmount);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(distributor.totalDeposited(), depositAmount);
    }

    function testCanRegisterMaxDeposit() public {
        uint256 depositAmount = distributor.MAXIMUM_DEPOSIT();
        token.mint(treasury, depositAmount);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(distributor.totalDeposited(), depositAmount);
    }

    function testCanDepositAfterClaiming(
        uint128 firstDeposit,
        uint128 secondDeposit
    ) public {
        vm.assume(firstDeposit > 0);
        vm.assume(secondDeposit > 0);

        token.mint(treasury, firstDeposit);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        vm.prank(firstMember);
        distributor.claim(0);

        token.mint(treasury, secondDeposit);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        uint256 totalDeposit = uint256(firstDeposit) + uint256(secondDeposit);

        assertEq(distributor.totalDeposited(), totalDeposit);
        assertEq(
            token.balanceOf(address(distributor)),
            totalDeposit - token.balanceOf(firstMember)
        );
    }
}

contract DistributorRegisterTest is DistributorTest {
    address firstMember;
    address nonMember;
    address treasury;

    Distributor distributor;

    function setUp() public override {
        DistributorTest.setUp();

        firstMember = makeAddr("0");
        nonMember = makeAddr("nonMember");
        treasury = makeAddr("treasury");

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

    function testCanTrackUnaccountedTokens(
        uint128 depositAmount,
        uint128 transferAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(transferAmount > 0);

        token.mint(address(treasury), depositAmount);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(distributor.totalDeposited(), depositAmount);
        assertEq(distributor.unregisteredTokens(), 0);

        token.mint(address(distributor), transferAmount);

        assertEq(distributor.unregisteredTokens(), transferAmount);
        assertEq(distributor.totalDeposited(), depositAmount);
    }

    function testCanRegisterUnaccountedTokens(uint256 tokenAmount) public {
        vm.assume(tokenAmount > 0);
        vm.assume(tokenAmount < distributor.MAXIMUM_DEPOSIT());

        token.mint(address(distributor), tokenAmount);

        vm.prank(firstMember);
        distributor.register();

        assertEq(distributor.totalDeposited(), tokenAmount);
    }

    function testCannotRegisterIfNotAMember(uint256 tokenAmount) public {
        vm.assume(tokenAmount > 0);
        vm.assume(tokenAmount < distributor.MAXIMUM_DEPOSIT());

        token.mint(address(distributor), tokenAmount);

        vm.expectRevert(Distributor.NotAMember.selector);
        vm.prank(nonMember);
        distributor.register();
    }

    function testCanRegisterMaxDepositableTokens() public {
        uint256 tokenAmount = distributor.MAXIMUM_DEPOSIT();
        token.mint(address(distributor), tokenAmount);

        vm.prank(firstMember);
        distributor.register();

        assertEq(distributor.totalDeposited(), tokenAmount);
    }

    function testCannotRegisterZeroTokens() public {
        vm.expectRevert(Distributor.NothingToRegister.selector);
        vm.prank(firstMember);
        distributor.register();
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
        vm.assume(tokenAmount < distributor.MAXIMUM_DEPOSIT());

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
        vm.assume(tokenAmount < distributor.MAXIMUM_DEPOSIT());

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
