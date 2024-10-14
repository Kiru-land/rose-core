// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Rose} from "../src/Rose.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RoseTest is Test {

    Rose public rose;
    uint256 public constant R0_INIT = 1e17;
    uint256 public constant ALPHA = 1e5;
    uint256 public constant PHI = 1e4;
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant R1_INIT = 200_000_000 * 1e18;
    uint256 public constant FOR_SALE = 620_000_000 * 1e18;
    uint256 public constant TREASURY_ALLOCATION = 80_000_000 * 1e18;
    uint256 public constant CLAWBACK = 100_000_000 * 1e18;
    address public constant TREASURY = address(0x3);

    function setUp() public {
        rose = new Rose{salt: "REDROSE", value: R0_INIT}(
            ALPHA, 
            PHI, 
            R1_INIT, 
            SUPPLY,
            TREASURY
        );
    }

    // Test the approve function
    function testApprove(address to, uint value) public {
        // Checks if the approval mechanism works correctly
        // Verifies initial allowance is 0, then approves a value, and confirms the new allowance
        assertEq(rose.allowance(address(this), to), 0);

        assertTrue(rose.approve(to, value));

        assertEq(rose.allowance(address(this), to), value);
    }

    // Test the transfer function
    function testTransfer(address from, address to, uint value) public {
        // Ensures the transfer function works as expected
        // Mints tokens, transfers them, and verifies balances are updated correctly
        vm.assume(to != address(this));
        vm.assume(from != address(rose));
        vm.assume(from != to);
        vm.assume(from != address(this));
        vm.assume(from != TREASURY);

        mint(from, value);

        uint selfInitialRoseBalance = rose.balanceOf(from);
        uint toInitialRoseBalance = rose.balanceOf(to);

        vm.prank(from);
        rose.transfer(to, value);

        assertEq(rose.balanceOf(from), selfInitialRoseBalance - value);
        assertEq(rose.balanceOf(to), toInitialRoseBalance + value);
    }

    // Test transfer failure due to insufficient balance
    function testTransferNotEnoughBalance(address from,address to, uint balance, uint value) public {
        // Verifies that a transfer fails when the sender doesn't have enough balance
        vm.assume(from != address(rose));
        vm.assume(from != to);
        vm.assume(from != address(this));
        vm.assume(value > balance);
        vm.assume(from != TREASURY);

        mint(from, balance);

        vm.prank(from);
        vm.expectRevert();
        rose.transfer(to, value);
    }


    // Test the transferFrom function
    function testTransferFrom(address from, address to, uint value) public {
        // Checks if transferFrom works correctly
        // Mints tokens, approves spending, transfers tokens, and verifies balances
        vm.assume(address(this) != from);
        vm.assume(from != to);
        vm.assume(to != address(rose));
        vm.assume(from != TREASURY);

        mint(from, value);

        uint fromInitialRoseBalance = rose.balanceOf(from);
        uint toInitialRoseBalance = rose.balanceOf(to);

        vm.prank(from);
        rose.approve(to, value);
        
        vm.prank(to);
        rose.transferFrom(from, to, value);

        assertEq(rose.balanceOf(from), fromInitialRoseBalance - value);
        assertEq(rose.balanceOf(to), toInitialRoseBalance + value);
    }

    // Test transferFrom failure due to insufficient allowance
    function testFailTransferFromNotEnoughAllowance(address from, address to, uint allowance, uint value) public {
        // Ensures transferFrom fails when the spender doesn't have enough allowance
        vm.assume(value > 0);
        vm.assume(allowance < value);
        mint(from, value);
        
        vm.startPrank(from);
        rose.approve(address(this), allowance);
        vm.stopPrank();

        assertTrue(rose.transferFrom(from, to, value));
    }

    // Test transferFrom failure due to insufficient balance
    function testTransferFromNotEnoughBalance(address from, address to, uint balance, uint value) public {
        // Verifies that transferFrom fails when the sender doesn't have enough balance
        vm.assume(from != address(rose));
        vm.assume(from != to);
        vm.assume(from != address(this));
        vm.assume(value > balance);
        vm.assume(from != TREASURY);

        mint(from, balance);

        vm.startPrank(from);
        rose.approve(to, value);
        vm.stopPrank();
        
        vm.prank(to);
        vm.expectRevert();
        rose.transferFrom(from, to, value);
    }

    // Test the buy (deposit) function
    function testBuy(uint value) public {
        // Checks if the deposit function works correctly
        // Verifies token balances, ETH balances, and contract state after a purchase
        vm.assume(value < address(this).balance);
        (uint r0, uint r1, uint alpha) = rose.getState();
        uint selfInitialRoseBalance = rose.balanceOf(address(this));
        uint selfInitialWethBalance = address(this).balance;
        uint quote = rose.quoteDeposit(value);

        rose.deposit{value: value}(quote);
        
        // assertEq(quote, out);

        (uint r0Prime, uint r1Prime, uint alphaPrime) = rose.getState();
        assertEq(address(this).balance, selfInitialWethBalance - value);
        assertLe(rose.balanceOf(address(rose)), r1);
        assertGe(address(rose).balance, r0);
        assertGe(rose.balanceOf(address(this)), selfInitialRoseBalance);
        assertEq(r0Prime, address(rose).balance);
        assertEq(r1Prime, rose.balanceOf(address(rose)));
        assertEq(r0Prime, r0 + value);
        assertGe(r0Prime, r0);
        assertLe(r1Prime, r1);
        assertGe(alphaPrime, alpha);
        if (r1 > 0 && r1Prime > 0) {
            assertGe(r0Prime * 1e6 / r1Prime, r0 * 1e6 / r1);
        }
    }

    // Test the sell (withdraw) function
    function testSell(uint value) public {
        // Ensures the withdraw function works as expected
        // Verifies token balances, ETH balances, and contract state after a sale
        vm.assume(value <= rose.balanceOf(address(rose)) / 50);
        mint(address(this), value);
        uint selfInitialRoseBalance = rose.balanceOf(address(this));
        uint selfInitialWethBalance = address(this).balance;
        (uint r0, uint r1, uint alpha) = rose.getState();
        uint quote = rose.quoteWithdraw(value);

        rose.withdraw(value, quote);
        // assertEq(quote, out);

        (uint r0Prime, uint r1Prime, uint alphaPrime) = rose.getState();
        uint fees = address(rose).balance - r0Prime;
        assertEq(address(rose).balance, r0Prime + fees);
        assertEq(rose.balanceOf(address(rose)), r1Prime);
        assertEq(rose.balanceOf(address(this)), selfInitialRoseBalance - value);
        assertEq(address(this).balance, selfInitialWethBalance + (r0 - (r0Prime + fees)));
        assertGe(address(this).balance, selfInitialWethBalance);
        assertLe(r0Prime, r0);
        assertGe(r1Prime, r1);
        assertGe(alpha, alphaPrime);
        assertLe(r0Prime * 1e6 / r1Prime, r0 * 1e6 / r1);
    }

    // Test the collect function
    function testCollect(uint value) public {
        // Checks if the collect function correctly transfers fees to the treasury
        // Verifies ETH balances before and after fee collection
        vm.assume(value <= rose.balanceOf(address(rose)) / 50);
        mint(address(this), value);
        assertEq(rose.balanceOf(address(this)), value);
        uint treasuryInitialWethBalance = address(rose.TREASURY()).balance;
        uint roseInitialWethBalance = address(rose).balance;
        
        assertTrue(rose.transfer(address(rose), value));

        (uint r0, uint r1, uint alpha) = rose.getState();
        uint fees = address(rose).balance - r0;

        vm.startPrank(rose.TREASURY());
        rose.collect();
        vm.stopPrank();

        assertEq(roseInitialWethBalance, address(rose).balance + fees);
        assertEq(treasuryInitialWethBalance + fees, address(rose.TREASURY()).balance);
    }

    function mint(address to, uint value) internal {
        bytes32 TO_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, to)
            mstore(add(ptr, 0x20), 0)
            TO_BALANCE_SLOT := keccak256(ptr, 0x40)
        }
        vm.store(address(rose), TO_BALANCE_SLOT, bytes32(value));
    }

    receive() external payable {}
}
