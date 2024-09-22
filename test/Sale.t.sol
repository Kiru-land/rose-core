// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Sale.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

contract MockToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("MockToken", "MTK") {
        _mint(msg.sender, initialSupply);
    }
}

contract SaleTest is Test {
    PublicSale public sale;
    MockToken public token;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant TO_SELL = 1_000_000 * 1e18;
    uint256 public constant SOFT_CAP = 100 ether;
    uint256 public constant HARD_CAP = 200 ether;
    uint256 public constant DURATION = 7 days;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        token = new MockToken(INITIAL_SUPPLY);

        sale = new PublicSale(address(token), TO_SELL, SOFT_CAP, HARD_CAP, DURATION);

        token.transfer(address(sale), INITIAL_SUPPLY);

        vm.deal(user1, 150 ether);
        vm.deal(user2, 150 ether);
    }

    function testInitialState() public {
        assertEq(sale.TOKEN(), address(token));
        assertEq(sale.SOFT_CAP(), SOFT_CAP);
        assertEq(sale.HARD_CAP(), HARD_CAP);
        assertEq(sale.SALE_END(), block.timestamp + DURATION);
        assertEq(sale.totalRaised(), 0);
        assertFalse(sale.saleEnded());
    }

    function testContribute() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 50 ether}("");
        assertTrue(success);

        assertEq(sale.totalRaised(), 50 ether);
        assertEq(getContribution(user1), 50 ether);
    }

    function testFailContributeFailsAfterEndTime() public {
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(user1);
        vm.expectRevert();
        (bool success, ) = address(sale).call{value: 50 ether}("");
        assertFalse(success);
    }

    function testEndSale() public {
        vm.warp(block.timestamp + DURATION);
        sale.endSale();
        assertTrue(sale.saleEnded());
    }

    function testFailSaleFailsBeforeEndTime() public {
        vm.warp(block.timestamp + DURATION - 1);
        vm.expectRevert();
        sale.endSale();
    }

    function testClaimRefundWhenSoftCapNotReached() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 50 ether}("");
        assertTrue(success);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        sale.claim();

        assertEq(user1.balance - balanceBefore, 50 ether);
        assertTrue(getHasClaimed(user1));
    }

    function testClaimTokensWhenSoftCapReached() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 101 ether}("");
        assertTrue(success);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        console.log("balanceOf user1", token.balanceOf(user1));
        console.log("balance of sale", token.balanceOf(address(sale)));
        console.log("user eth balance after deposit", user1.balance / 1e18);
        console.log("balanceOf sale", address(sale).balance / 1e18);
        console.log("soft cap", sale.SOFT_CAP() / 1e18);
        console.log("hard cap", sale.HARD_CAP() / 1e18);
        console.log("total raised", sale.totalRaised() / 1e18);

        vm.prank(user1);
        sale.claim();

        

        // assertGt(token.balanceOf(user1), tokenBalanceBefore);
        // assertTrue(getHasClaimed(user1));
    }

    function testClaimTokensAndRefundWhenOversubscribed() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 100 ether}("");
        assertTrue(success);
        vm.prank(user2);
        (success, ) = address(sale).call{value: 150 ether}("");
        assertTrue(success);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user2);
        uint256 balanceBefore = user2.balance;
        uint256 tokenBalanceBefore = token.balanceOf(user2);
        sale.claim();

        assertGt(user2.balance, balanceBefore);
        assertGt(token.balanceOf(user2), tokenBalanceBefore);
        assertTrue(getHasClaimed(user2));
    }

    function testFailCannotClaimTwice() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 5 ether}("");
        assertTrue(success, "Contribution failed");

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        sale.claim();

        vm.expectRevert();
        vm.prank(user1);
        sale.claim();
    }

    // function testFailCannotClaimIfNotContributed() public {
    //     vm.warp(block.timestamp + DURATION);
    //     sale.endSale();

    //     vm.expectRevert();
    //     vm.prank(user1);
    //     sale.claim();
    // }

    function getContribution(address addr) public view returns (uint256) {
        bytes32 CONTRIB_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, addr)
            mstore(add(ptr, 0x20), 2)
            CONTRIB_SLOT := keccak256(ptr, 0x40)
        }
        return uint256(vm.load(address(sale), CONTRIB_SLOT));
    }

    function getHasClaimed(address addr) public view returns (bool) {
        bytes32 HAS_CLAIMED_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, addr)
            mstore(add(ptr, 0x20), 3)
            HAS_CLAIMED_SLOT := keccak256(ptr, 0x40)
        }
        return vm.load(address(sale), HAS_CLAIMED_SLOT) != bytes32(0);
    }

    receive() external payable {}
}
