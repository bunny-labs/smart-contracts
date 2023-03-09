// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "solmate/tokens/ERC20.sol";
import "openzeppelin-contracts/utils/Strings.sol";
import "openzeppelin-contracts/proxy/Clones.sol";
import "bunny-libs/MembershipToken/MembershipToken.sol";

import "src/Distributor/Distributor.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TEST", 18) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract DistributorTest is Test {
    TestToken token;

    address member = makeAddr("0");
    address source = makeAddr("source");
    address deployer = makeAddr("deployer");

    Distributor distributor;
    Distributor.CloningConfig defaultCloningConfig;

    function setUp() public virtual {
        vm.label(member, "Member 0");
        vm.label(source, "Distribution source");
        vm.label(deployer, "Contract deployer");

        token = new TestToken();
        defaultCloningConfig = Clonable.CloningConfig({author: deployer, feeBps: 2500, feeRecipient: deployer});
        distributor = new Distributor(
            "Vcooors",
            "VCOOOR",
            setupMembers(38),
            defaultCloningConfig
        );
    }

    function expand16(uint16 seed, uint256 size) public pure returns (uint16[] memory) {
        uint16[] memory numbers = new uint16[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint16(uint256(keccak256(abi.encodePacked(seed, i))) % type(uint16).max);
        }
        return numbers;
    }

    function setupMembers(uint256 memberCount) public returns (MembershipToken.Membership[] memory) {
        MembershipToken.Membership[] memory members = new MembershipToken.Membership[](memberCount);
        uint16[] memory shares = expand16(uint16(memberCount % type(uint16).max), memberCount);

        for (uint256 i; i < memberCount; i++) {
            members[i] = MembershipToken.Membership(makeAddr(Strings.toString(uint256(i))), shares[i]);
        }

        return members;
    }

    function testCanBeDeployed(
        string memory name,
        string memory symbol,
        uint8 memberCount,
        address author,
        uint8 feeBps,
        address feeRecipient
    ) public {
        Distributor.Membership[] memory members = setupMembers(memberCount);
        distributor = new Distributor(name, symbol, members, Clonable.CloningConfig({
            author: author, feeBps: feeBps,feeRecipient: feeRecipient}));

        assertEq(distributor.name(), name);
        assertEq(distributor.symbol(), symbol);
        assertEq(distributor.totalSupply(), members.length);
        assertEq(distributor.CONTRACT_VERSION(), 2_00);

        assertEq(distributor.cloningConfig().author, author);
        assertEq(distributor.cloningConfig().feeBps, feeBps);
        assertEq(distributor.cloningConfig().feeRecipient, feeRecipient);

        for (uint256 i = 0; i < memberCount; i++) {
            assertEq(distributor.membershipWeight(i), members[i].weight);
        }
    }

    function testCanBeCloned(string memory name, string memory symbol, uint8 memberCount) public {
        Distributor.Membership[] memory members = setupMembers(memberCount);
        Distributor clone = Distributor(payable(distributor.clone(distributor.encodeInitdata(name, symbol, members))));

        assertEq(clone.name(), name);
        assertEq(clone.symbol(), symbol);
        assertEq(clone.totalSupply(), members.length);
        assertEq(clone.CONTRACT_VERSION(), 2_00);

        assertEq(distributor.cloningConfig().author, defaultCloningConfig.author);
        assertEq(distributor.cloningConfig().feeBps, defaultCloningConfig.feeBps);
        assertEq(distributor.cloningConfig().feeRecipient, defaultCloningConfig.feeRecipient);

        for (uint256 i = 0; i < memberCount; i++) {
            assertEq(clone.membershipWeight(i), members[i].weight);
        }
    }

    function testCannotDistributeUnlessAMember() public {
        vm.expectRevert(MembershipToken.NotAMember.selector);
        distributor.distribute(address(token), source);

        vm.expectRevert(MembershipToken.NotAMember.selector);
        distributor.distribute(address(token), source, 1);

        vm.expectRevert(MembershipToken.NotAMember.selector);
        distributor.distribute();
    }

    function testCannotDistributeWithoutApproval() public {
        token.mint(source, distributor.totalWeights());

        vm.expectRevert();
        vm.prank(member);
        distributor.distribute(address(token), source);
    }

    function testCanDistributeFullERC20BalanceFromSourceAddress(uint8 distributionMultiplier) public {
        uint256 distributionAmount = uint256(distributor.totalWeights()) * distributionMultiplier;
        token.mint(source, distributionAmount);
        assertEq(token.balanceOf(source), distributionAmount);

        vm.prank(source);
        token.approve(address(distributor), type(uint256).max);

        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(token.balanceOf(distributor.ownerOf(i)), 0);
        }

        vm.prank(member);
        distributor.distribute(address(token), source);

        assertEq(token.balanceOf(source), 0);
        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(
                token.balanceOf(distributor.ownerOf(i)),
                uint256(distributor.membershipWeight(i)) * distributionMultiplier
            );
        }
    }

    function testCanDistributeFullERC20BalanceFromOwnAddress(uint8 distributionMultiplier) public {
        uint256 distributionAmount = uint256(distributor.totalWeights()) * distributionMultiplier;
        token.mint(address(distributor), distributionAmount);
        assertEq(token.balanceOf(address(distributor)), distributionAmount);

        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(token.balanceOf(distributor.ownerOf(i)), 0);
        }

        vm.prank(member);
        distributor.distribute(address(token), address(distributor));

        assertEq(token.balanceOf(address(distributor)), 0);
        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(
                token.balanceOf(distributor.ownerOf(i)),
                uint256(distributor.membershipWeight(i)) * distributionMultiplier
            );
        }
    }

    function testCanDistributePartialERC20BalanceFromSourceAddress(uint8 distributionMultiplier, uint8 extraMultiplier)
        public
    {
        uint256 distributionAmount = uint256(distributor.totalWeights()) * distributionMultiplier;
        uint256 extraAmount = uint256(distributor.totalWeights()) * extraMultiplier;

        token.mint(source, distributionAmount + extraAmount);
        assertEq(token.balanceOf(source), distributionAmount + extraAmount);

        vm.prank(source);
        token.approve(address(distributor), type(uint256).max);

        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(token.balanceOf(distributor.ownerOf(i)), 0);
        }

        vm.prank(member);
        distributor.distribute(address(token), source, distributionAmount);

        assertEq(token.balanceOf(source), extraAmount);
        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(
                token.balanceOf(distributor.ownerOf(i)),
                uint256(distributor.membershipWeight(i)) * distributionMultiplier
            );
        }
    }

    function testCanDistributePartialERC20BalanceFromOwnAddress(uint8 distributionMultiplier, uint8 extraMultiplier)
        public
    {
        uint256 distributionAmount = uint256(distributor.totalWeights()) * distributionMultiplier;
        uint256 extraAmount = uint256(distributor.totalWeights()) * extraMultiplier;

        token.mint(address(distributor), distributionAmount + extraAmount);
        assertEq(token.balanceOf(address(distributor)), distributionAmount + extraAmount);

        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(token.balanceOf(distributor.ownerOf(i)), 0);
        }

        vm.prank(member);
        distributor.distribute(address(token), address(distributor), distributionAmount);

        assertEq(token.balanceOf(address(distributor)), extraAmount);
        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(
                token.balanceOf(distributor.ownerOf(i)),
                uint256(distributor.membershipWeight(i)) * distributionMultiplier
            );
        }
    }

    function testCanReceiveEther(uint224 amount) public {
        vm.deal(member, amount);

        vm.prank(member);
        payable(address(distributor)).transfer(amount);
    }

    function testCanDistributeFullEtherBalanceFromOwnAddress(uint8 distributionMultiplier) public {
        uint256 distributionAmount = uint256(distributor.totalWeights()) * distributionMultiplier;
        vm.deal(address(distributor), distributionAmount);
        assertEq(address(distributor).balance, distributionAmount);

        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(distributor.ownerOf(i).balance, 0);
        }

        vm.prank(member);
        distributor.distribute();

        assertEq(address(distributor).balance, 0);
        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(distributor.ownerOf(i).balance, uint256(distributor.membershipWeight(i)) * distributionMultiplier);
        }
    }

    function testDistributionDestinationFollowsToken(uint8 transferCount) public {
        MembershipToken.Membership[] memory members = new MembershipToken.Membership[](1);
        members[0] = MembershipToken.Membership(member, type(uint32).max);
        distributor = new Distributor("Vcooors", "VCOOOR", members, defaultCloningConfig);

        address oldMember = member;
        for (uint256 i = 1; i < transferCount; i++) {
            address newMember = makeAddr(vm.toString(i));

            assertEq(distributor.balanceOf(oldMember), 1);
            assertEq(distributor.balanceOf(newMember), 0);
            vm.prank(oldMember);
            distributor.transferFrom(oldMember, newMember, 0);
            assertEq(distributor.balanceOf(oldMember), 0);
            assertEq(distributor.balanceOf(newMember), 1);

            assertEq(address(distributor).balance, 0);
            vm.deal(address(distributor), 420);
            assertEq(address(distributor).balance, 420);

            assertEq(newMember.balance, 0);
            vm.prank(newMember);
            distributor.distribute();
            assertEq(newMember.balance, 420);
            assertEq(address(distributor).balance, 0);

            oldMember = newMember;
        }
    }

    function testCanDistributeLargeAmounts(uint32 extraAmount) public {
        vm.assume(extraAmount > 0);

        MembershipToken.Membership[] memory members = new MembershipToken.Membership[](1);
        members[0] = MembershipToken.Membership(member, type(uint32).max);

        distributor = new Distributor("Vcooors", "VCOOOR", members, defaultCloningConfig);

        uint256 distributionAmount = uint256(type(uint224).max) + extraAmount;
        token.mint(source, distributionAmount);
        assertEq(token.balanceOf(source), distributionAmount);

        vm.prank(source);
        token.approve(address(distributor), type(uint256).max);

        vm.prank(member);
        distributor.distribute(address(token), source);
        assertEq(token.balanceOf(source), extraAmount);

        vm.prank(member);
        distributor.distribute(address(token), source);
        assertEq(token.balanceOf(source), 0);
    }

    function testCanSimulateDistribution() public view {
        distributor.simulate(distributor.totalWeights());
    }
}
