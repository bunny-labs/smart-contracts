// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "openzeppelin-contracts/utils/Strings.sol";

import "../src/Distributor/PullDistributor.sol";
import "../src/MembershipToken/MembershipToken.sol";
import "./Utils.sol";

contract PullDistributorTest is Test {
    PullDistributor distributor;
    TestToken token;

    address firstMember;
    address nonMember;
    address treasury;

    function setUp() public virtual {
        token = new TestToken();

        firstMember = makeAddr("0");
        nonMember = makeAddr("nonMember");
        treasury = makeAddr("treasury");
    }

    function setupMembers(uint256 memberCount)
        public
        returns (MembershipToken.Membership[] memory)
    {
        MembershipToken.Membership[]
            memory members = new MembershipToken.Membership[](memberCount);
        uint16[] memory shares = Utils.expand16(
            uint16(memberCount % type(uint16).max),
            memberCount
        );

        for (uint256 i; i < memberCount; i++) {
            members[i] = MembershipToken.Membership(
                makeAddr(Strings.toString(uint256(i))),
                shares[i]
            );
        }

        return members;
    }
}

contract PullDistributorInitializationTest is PullDistributorTest {
    function setUp() public override {
        PullDistributorTest.setUp();
    }

    function testCanInitialize(
        string memory name,
        string memory symbol,
        address token,
        uint8 memberCount
    ) public {
        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: name,
                symbol: symbol,
                token: token,
                members: setupMembers(memberCount)
            })
        );

        assertEq(distributor.name(), name);
        assertEq(distributor.symbol(), symbol);
        assertEq(address(distributor.token()), token);
        assertEq(distributor.totalSupply(), memberCount);

        assertEq(distributor.CONTRACT_VERSION(), 1_00);
        assertEq(distributor.totalDeposited(), 0);
        assertEq(distributor.totalClaimed(), 0);
    }

    function testCanQueryMetadata(uint8 memberCount) public {
        vm.assume(memberCount > 0);

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(memberCount)
            })
        );

        for (uint16 i; i < memberCount; i++) {
            distributor.tokenURI(i);
        }

        vm.expectRevert();
        distributor.tokenURI(memberCount);
    }
}

contract PullDistributorDepositTest is PullDistributorTest {
    function setUp() public override {
        PullDistributorTest.setUp();

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(38)
            })
        );

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);
    }

    function testCanDeposit(uint224 amount) public {
        vm.assume(amount > 0);

        token.mint(treasury, amount);

        assertEq(token.balanceOf(treasury), amount);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(distributor.totalDeposited(), 0);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(distributor.totalDeposited(), amount);
    }

    function testCanDepositByAnyMember(uint208 amount) public {
        vm.assume(amount > 0);

        uint16 totalSupply = distributor.totalSupply();
        for (uint16 i; i < totalSupply; i++) {
            token.mint(treasury, amount);

            vm.prank(makeAddr(Strings.toString(i)));
            distributor.deposit(treasury);
        }

        assertEq(
            distributor.totalDeposited(),
            uint256(amount) * uint256(totalSupply)
        );
    }

    function testCannotDepositIfNotAMember() public {
        token.mint(treasury, 420);

        vm.expectRevert(MembershipToken.NotAMember.selector);
        vm.prank(nonMember);
        distributor.deposit(treasury);
    }

    function testCanDepositMaxAmount() public {
        uint256 amount = type(uint224).max;

        token.mint(treasury, amount);

        vm.prank(firstMember);
        distributor.deposit(treasury);

        assertEq(token.balanceOf(treasury), 0);
        assertEq(token.balanceOf(address(distributor)), amount);
        assertEq(distributor.totalDeposited(), amount);
    }

    function testCannotDepositOverMaxAmount() public {
        uint256 amount = uint256(type(uint224).max) + 1;
        token.mint(treasury, amount);

        vm.expectRevert(PullDistributor.TooLargeDeposit.selector);
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCannotDepositFromEmptyAddress() public {
        vm.expectRevert(PullDistributor.NothingToDeposit.selector);
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

contract PullDistributorRegisterTest is PullDistributorTest {
    function setUp() public override {
        PullDistributorTest.setUp();

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(38)
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

        uint256 totalAmount = uint256(depositAmount) + uint256(transferAmount);

        // We start with an empty contract and transfer tokens in
        token.mint(address(distributor), transferAmount);

        // Should have that amount of unregistered tokens now
        assertEq(distributor.unregisteredTokens(), transferAmount);

        // Now we deposit another amount from the treasury
        token.mint(address(treasury), depositAmount);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        // Deposit should register both transferred tokens as well as previously unregistered ones
        assertEq(distributor.totalDeposited(), totalAmount);
        assertEq(distributor.unregisteredTokens(), 0);

        // Let's try another direct transfer
        token.mint(address(distributor), transferAmount);

        // Should show up as unregistered on top of all the deposited tokens
        assertEq(distributor.unregisteredTokens(), transferAmount);
        assertEq(distributor.totalDeposited(), totalAmount);
    }

    function testCanRegisterUnaccountedTokens(uint224 tokenAmount) public {
        vm.assume(tokenAmount > 0);

        token.mint(address(distributor), tokenAmount);

        assertEq(distributor.totalDeposited(), 0);

        vm.prank(firstMember);
        distributor.register();

        assertEq(distributor.totalDeposited(), tokenAmount);
    }

    function testCannotRegisterZeroTokens() public {
        vm.expectRevert(PullDistributor.NothingToRegister.selector);
        vm.prank(firstMember);
        distributor.register();
    }

    function testCannotRegisterIfNotAMember() public {
        token.mint(address(distributor), 420);

        vm.expectRevert(MembershipToken.NotAMember.selector);
        vm.prank(nonMember);
        distributor.register();
    }
}

contract PullDistributorClaimTest is PullDistributorTest {
    function setUp() public override {
        PullDistributorTest.setUp();

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                token: address(token),
                members: setupMembers(38)
            })
        );

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);
    }

    function testCanClaimTokens() public {
        uint16 memberCount = distributor.totalSupply();
        uint256 totalTokens = distributor.totalWeights();

        token.mint(treasury, totalTokens);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        for (uint16 i; i < memberCount; i++) {
            address member = makeAddr(Strings.toString(i));

            assertEq(token.balanceOf(member), 0);
            assertEq(distributor.memberClaimed(i), 0);

            vm.prank(member);
            distributor.claim(i);

            assertEq(token.balanceOf(member), distributor.membershipWeight(i));
            assertEq(distributor.memberClaimed(i), token.balanceOf(member));
        }

        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(distributor.totalClaimed(), totalTokens);
    }

    function testCanClaimFromMaxDeposit() public {
        uint16 memberCount = distributor.totalSupply();
        uint256 tokenAmount = type(uint224).max;

        token.mint(treasury, tokenAmount);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        for (uint16 i; i < memberCount; i++) {
            address memberAddress = makeAddr(Strings.toString(i));
            vm.prank(memberAddress);
            distributor.claim(i);
        }

        assertLt(token.balanceOf(address(distributor)), memberCount);
    }

    function testCannotClaimIfNotAMember() public {
        token.mint(treasury, 420);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        vm.expectRevert(PullDistributor.NotYourToken.selector);
        vm.prank(nonMember);
        distributor.claim(0);
    }

    function testCannotClaimIfNotYourToken(uint224 tokenAmount) public {
        uint16 memberCount = distributor.totalSupply();
        vm.assume(tokenAmount >= memberCount);

        token.mint(treasury, tokenAmount);
        vm.prank(firstMember);
        distributor.deposit(treasury);

        for (uint16 i; i < memberCount; i++) {
            address memberAddress = makeAddr(
                Strings.toString((i + 1) % memberCount)
            );

            vm.expectRevert(PullDistributor.NotYourToken.selector);
            vm.prank(memberAddress);
            distributor.claim(i);
        }
    }
}
