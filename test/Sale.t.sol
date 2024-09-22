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

        vm.deal(user1, 250 ether);
        vm.deal(user2, 250 ether);
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

        // Contribution is the raised amount
        assertEq(sale.totalRaised(), 50 ether);
        // User's contribution has been added
        assertEq(getContribution(user1), 50 ether);
    }

    function testFailContributeFailsAfterEndTime() public {
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(user1);
        vm.expectRevert();
        (bool success, ) = address(sale).call{value: 50 ether}("");
        // User couldnt contribute after sale ended
        assertFalse(success);
    }

    function testEndSale() public {
        vm.warp(block.timestamp + DURATION);
        sale.endSale();
        // Sale is ended
        assertTrue(sale.saleEnded());
    }

    function testFailSaleFailsBeforeEndTime() public {
        vm.warp(block.timestamp + DURATION - 1);
        // Reverts because sale is not ended
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
        // User got refunded of their ETH
        assertEq(user1.balance, balanceBefore + 50 ether);
        // User has claimed
        assertTrue(getHasClaimed(user1));
    }

    function testClaimTokensWhenSoftCapReached() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 101 ether}("");
        assertTrue(success);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        sale.claim();

        // User received his share of tokens
        assertEq(token.balanceOf(user1), (sale.totalRaised() * sale.TO_SELL()) / getContribution(user1));
        // User's ETH balance is unchanged
        assertEq(user1.balance, balanceBefore);
        // Sale contract has no tokens left
        assertEq(token.balanceOf(address(sale)), 0);
        // User has claimed
        assertTrue(getHasClaimed(user1));
    }

    function testClaimTokensAndRefundWhenOversubscribed() public {
        uint256 contribution = 250 ether;
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: contribution}("");
        assertTrue(success);

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        sale.claim();

        // User received his share of tokens
        assertEq(token.balanceOf(user1), (sale.totalRaised() * sale.TO_SELL()) / getContribution(user1));
        // User has been refunded of their excess ETH
        assertEq(user1.balance, contribution - address(sale).balance);
        // Sale contract has no tokens left
        assertEq(token.balanceOf(address(sale)), 0);
        // User has claimed
        assertTrue(getHasClaimed(user1));
    }

    function testFailCannotClaimTwice() public {
        vm.prank(user1);
        (bool success, ) = address(sale).call{value: 5 ether}("");
        assertTrue(success, "Contribution failed");

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        sale.claim();

        vm.prank(user1);
        vm.expectRevert();
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
