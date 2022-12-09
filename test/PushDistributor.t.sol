// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "openzeppelin-contracts/utils/Strings.sol";

import "../src/Distributor/PushDistributor.sol";
import "../src/MembershipToken/MembershipToken.sol";
import "./Utils.sol";

contract PushDistributorTest is Test {
    TestToken token;

    address source;
    address member;

    function setUp() public virtual {
        token = new TestToken();

        source = makeAddr("source");
        vm.label(source, "Distribution source");

        member = makeAddr("0");
        vm.label(source, "Member");
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

    function testCanInitialize(
        string memory name,
        string memory symbol,
        uint8 memberCount
    ) public {
        PushDistributor.Membership[] memory members = setupMembers(memberCount);
        PushDistributor distributor = new PushDistributor(
            PushDistributor.Configuration(name, symbol, members)
        );

        assertEq(distributor.name(), name);
        assertEq(distributor.symbol(), symbol);
        assertEq(distributor.totalSupply(), members.length);
        assertEq(distributor.CONTRACT_VERSION(), 1_00);

        for (uint256 i = 0; i < memberCount; i++) {
            assertEq(distributor.membershipWeight(i), members[i].weight);
        }
    }

    function testCannotDistributeWithoutApproval() public {
        PushDistributor distributor = new PushDistributor(
            PushDistributor.Configuration("Vcooors", "VCOOOR", setupMembers(38))
        );

        token.mint(source, 420);

        vm.expectRevert();
        vm.prank(member);
        distributor.distribute(address(token), source);
    }

    function testCannotDistributeUnlessAMember() public {
        PushDistributor distributor = new PushDistributor(
            PushDistributor.Configuration("Vcooors", "VCOOOR", setupMembers(38))
        );

        vm.expectRevert(MembershipToken.NotAMember.selector);
        distributor.distribute(address(token), source);
    }

    function testCanDistributeProportionally(uint200 multiplier) public {
        PushDistributor distributor = new PushDistributor(
            PushDistributor.Configuration("Vcooors", "VCOOOR", setupMembers(38))
        );

        uint256 distributionAmount = uint256(distributor.totalWeights()) *
            multiplier;
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
                uint256(distributor.membershipWeight(i)) * multiplier
            );
        }
    }

    function testCanDistributeLargeAmounts(uint32 extraAmount) public {
        vm.assume(extraAmount > 0);

        MembershipToken.Membership[]
            memory members = new MembershipToken.Membership[](1);
        members[0] = MembershipToken.Membership(member, type(uint32).max);

        PushDistributor distributor = new PushDistributor(
            PushDistributor.Configuration("Vcooors", "VCOOOR", members)
        );

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
