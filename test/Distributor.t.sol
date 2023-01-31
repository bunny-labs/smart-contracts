// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "solmate/tokens/ERC20.sol";
import "openzeppelin-contracts/utils/Strings.sol";
import "openzeppelin-contracts/proxy/Clones.sol";

import "../src/Distributor/Distributor.sol";
import "../src/MembershipToken/MembershipToken.sol";

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

    function expand16(uint16 seed, uint256 size)
        public
        pure
        returns (uint16[] memory)
    {
        uint16[] memory numbers = new uint16[](size);
        for (uint256 i; i < size; i++) {
            numbers[i] = uint16(
                uint256(keccak256(abi.encodePacked(seed, i))) % type(uint16).max
            );
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
        Distributor clone = Distributor(distributor.clone(distributor.encodeInitdata(name, symbol, members)));

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

    function testCannotDistributeWithoutApproval() public {
        token.mint(source, 420);

        vm.expectRevert();
        vm.prank(member);
        distributor.distribute(address(token), source);
    }

    function testCannotDistributeUnlessAMember() public {
        vm.expectRevert(MembershipToken.NotAMember.selector);
        distributor.distribute(address(token), source);
    }

    function testCanDistributeProportionally(uint200 multiplier) public {
        uint256 distributionAmount = uint256(distributor.totalWeights()) * multiplier;
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
            assertEq(token.balanceOf(distributor.ownerOf(i)), uint256(distributor.membershipWeight(i)) * multiplier);
        }
    }

    function testCanDistributeAfterTransferring() public {
        uint256 distributionAmount = uint256(distributor.totalWeights());
        token.mint(source, distributionAmount);
        assertEq(token.balanceOf(source), distributionAmount);

        vm.prank(source);
        token.approve(address(distributor), type(uint256).max);

        for (uint256 i = 1; i < distributor.totalSupply(); i++) {
            address oldMember = makeAddr(vm.toString(i));
            address newMember = makeAddr(vm.toString(i * 100));

            assertEq(distributor.balanceOf(oldMember), 1);
            assertEq(distributor.balanceOf(newMember), 0);
            assertEq(distributor.ownerOf(i), oldMember);

            vm.prank(oldMember);
            distributor.transferFrom(oldMember, newMember, i);

            assertEq(distributor.balanceOf(oldMember), 0);
            assertEq(distributor.balanceOf(newMember), 1);
            assertEq(distributor.ownerOf(i), newMember);
        }

        vm.prank(member);
        distributor.distribute(address(token), source);

        assertEq(token.balanceOf(source), 0);
        for (uint256 i; i < distributor.totalSupply(); i++) {
            assertEq(token.balanceOf(distributor.ownerOf(i)), uint256(distributor.membershipWeight(i)));
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
}
