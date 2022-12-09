// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "openzeppelin-contracts/utils/Strings.sol";

import "../src/Distributor/PullDistributor.sol";
import "../src/MembershipToken/MembershipToken.sol";
import "./Utils.sol";

contract PullDistributorTest is Test {
    TestToken token;

    function setUp() public virtual {
        token = new TestToken();
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

    function testCanInitialize() public {
        new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: "ipfs://hash",
                token: address(token),
                members: setupMembers(38)
            })
        );
    }

    function testCanInitializeImageURI(string memory imageURI) public {
        PullDistributor distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: imageURI,
                token: address(token),
                members: setupMembers(38)
            })
        );

        assertEq(distributor.imageURI(), imageURI);
    }

    function testCanInitializeAssetAddress(address testToken) public {
        PullDistributor distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: "ipfs://hash",
                token: testToken,
                members: setupMembers(38)
            })
        );

        assertEq(address(distributor.asset()), testToken);
    }
}

contract PullDistributorMetadataTest is PullDistributorTest {
    function setUp() public override {
        PullDistributorTest.setUp();
    }

    function testCanQueryMetadata() public {
        uint16 memberCount = 3;
        vm.assume(memberCount > 0);

        PullDistributor distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: "ipfs://hash",
                token: address(token),
                members: setupMembers(memberCount)
            })
        );

        for (uint16 i; i < memberCount; i++) {
            distributor.tokenURI(i);
        }
    }
}

contract PullDistributorDepositTest is PullDistributorTest {
    address treasury;
    address firstMember;

    PullDistributor distributor;

    function setUp() public override {
        PullDistributorTest.setUp();

        treasury = makeAddr("treasury");
        firstMember = makeAddr("0");

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: "ipfs://hash",
                token: address(token),
                members: setupMembers(38)
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

        uint16 totalSupply = distributor.totalSupply();
        for (uint16 i; i < totalSupply; i++) {
            address member = makeAddr(Strings.toString(i));
            token.mint(treasury, amount);
            vm.prank(member);
            distributor.deposit(treasury);
        }

        assertEq(
            distributor.totalDeposited(),
            uint256(amount) * uint256(totalSupply)
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

        vm.expectRevert(PullDistributor.TooLargeDeposit.selector);
        vm.prank(firstMember);
        distributor.deposit(treasury);
    }

    function testCannotDepositIfNotAMember() public {
        address nonMember = makeAddr("NotAMember");

        token.mint(treasury, 420);

        vm.expectRevert(MembershipToken.NotAMember.selector);
        vm.prank(nonMember);
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

contract PullDistributorRegisterTest is PullDistributorTest {
    address firstMember;
    address nonMember;
    address treasury;

    PullDistributor distributor;

    function setUp() public override {
        PullDistributorTest.setUp();

        firstMember = makeAddr("0");
        nonMember = makeAddr("nonMember");
        treasury = makeAddr("treasury");

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: "ipfs://hash",
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

        vm.expectRevert(MembershipToken.NotAMember.selector);
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
        vm.expectRevert(PullDistributor.NothingToRegister.selector);
        vm.prank(firstMember);
        distributor.register();
    }
}

contract PullDistributorClaimTest is PullDistributorTest {
    address treasury;
    address member;

    PullDistributor distributor;

    function setUp() public override {
        PullDistributorTest.setUp();

        treasury = makeAddr("treasury");
        member = makeAddr("0");

        distributor = new PullDistributor(
            PullDistributor.Configuration({
                name: "VCooors",
                symbol: "VCOOOR",
                imageURI: "ipfs://hash",
                token: address(token),
                members: setupMembers(38)
            })
        );

        vm.prank(treasury);
        token.approve(address(distributor), type(uint256).max);
    }

    function testCanClaimTokens(uint256 tokenAmount) public {
        uint16 memberCount = distributor.totalSupply();
        vm.assume(tokenAmount >= memberCount);
        vm.assume(tokenAmount < distributor.MAXIMUM_DEPOSIT());

        token.mint(treasury, tokenAmount);
        vm.prank(member);
        distributor.deposit(treasury);

        for (uint16 i; i < memberCount; i++) {
            address memberAddress = makeAddr(Strings.toString(i));
            vm.prank(memberAddress);
            distributor.claim(i);
        }

        // Only dust is left
        assertTrue(token.balanceOf(address(distributor)) < memberCount);
    }

    function testCanClaimFromMaxDeposit() public {
        uint16 memberCount = distributor.totalSupply();
        uint256 tokenAmount = distributor.MAXIMUM_DEPOSIT();

        token.mint(treasury, tokenAmount);
        vm.prank(member);
        distributor.deposit(treasury);

        for (uint16 i; i < memberCount; i++) {
            address memberAddress = makeAddr(Strings.toString(i));
            vm.prank(memberAddress);
            distributor.claim(i);
        }

        // Only dust is left
        assertLt(token.balanceOf(address(distributor)), memberCount);
    }

    function testCannotClaimIfNotAMember() public {
        token.mint(treasury, 420);
        vm.prank(member);
        distributor.deposit(treasury);

        address nonMember = makeAddr("NotAMember");
        vm.expectRevert(PullDistributor.NotYourToken.selector);
        vm.prank(nonMember);
        distributor.claim(0);
    }

    function testCannotClaimIfNotYourToken(uint256 tokenAmount) public {
        uint16 memberCount = distributor.totalSupply();
        vm.assume(tokenAmount >= memberCount);
        vm.assume(tokenAmount < distributor.MAXIMUM_DEPOSIT());

        token.mint(treasury, tokenAmount);
        vm.prank(member);
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
