// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/Sale.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("MockToken", "MTK") {
        _mint(msg.sender, initialSupply);
    }
}

contract OversubscribedTokenSaleTest is Test {
    OversubscribedTokenSale public sale;
    MockToken public token;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant SOFT_CAP = 100 ether;
    uint256 public constant HARD_CAP = 200 ether;
    uint256 public constant DURATION = 7 days;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        token = new MockToken(INITIAL_SUPPLY);
        sale = new OversubscribedTokenSale(IERC20(address(token)), SOFT_CAP, HARD_CAP, DURATION);

        token.transfer(address(sale), INITIAL_SUPPLY);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 150 ether);
    }

    function testInitialState() public {
        assertEq(address(sale.token()), address(token));
        assertEq(sale.softCap(), SOFT_CAP);
        assertEq(sale.hardCap(), HARD_CAP);
        assertEq(sale.saleEndTime(), block.timestamp + DURATION);
        assertEq(sale.totalRaised(), 0);
        assertFalse(sale.saleEnded());
    }

    function testContribute() public {
        vm.prank(user1);
        sale.contribute{value: 50 ether}();

        assertEq(sale.totalRaised(), 50 ether);
        assertEq(sale.contributions(user1), 50 ether);
    }

    function testContributeFailsAfterEndTime() public {
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(user1);
        vm.expectRevert("Sale has ended");
        sale.contribute{value: 50 ether}();
    }

    function testEndSale() public {
        vm.warp(block.timestamp + DURATION);
        sale.endSale();
        assertTrue(sale.saleEnded());
    }

    function testEndSaleFailsBeforeEndTime() public {
        vm.expectRevert("Sale has not ended yet");
        sale.endSale();
    }

    function testClaimRefundWhenSoftCapNotReached() public {
        vm.prank(user1);
        sale.contribute{value: 50 ether}();

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        uint256 balanceBefore = user1.balance;
        sale.claim();

        assertEq(user1.balance - balanceBefore, 50 ether);
        assertTrue(sale.hasClaimed(user1));
    }

    function testClaimTokensWhenSoftCapReached() public {
        vm.prank(user1);
        sale.contribute{value: 100 ether}();

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        uint256 tokenBalanceBefore = token.balanceOf(user1);
        sale.claim();

        assertGt(token.balanceOf(user1), tokenBalanceBefore);
        assertTrue(sale.hasClaimed(user1));
    }

    function testClaimTokensAndRefundWhenOversubscribed() public {
        vm.prank(user1);
        sale.contribute{value: 100 ether}();
        vm.prank(user2);
        sale.contribute{value: 150 ether}();

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user2);
        uint256 balanceBefore = user2.balance;
        uint256 tokenBalanceBefore = token.balanceOf(user2);
        sale.claim();

        assertGt(user2.balance, balanceBefore);
        assertGt(token.balanceOf(user2), tokenBalanceBefore);
        assertTrue(sale.hasClaimed(user2));
    }

    function testCannotClaimTwice() public {
        vm.prank(user1);
        sale.contribute{value: 50 ether}();

        vm.warp(block.timestamp + DURATION);
        sale.endSale();

        vm.prank(user1);
        sale.claim();

        vm.prank(user1);
        vm.expectRevert("Already claimed");
        sale.claim();
    }

    receive() external payable {}
}