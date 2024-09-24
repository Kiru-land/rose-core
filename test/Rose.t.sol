// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Rose} from "../src/Rose.sol";

contract RoseTest is Test {

    Rose public rose;
    uint public liquidityInit = 1e24;

    function setUp() public {
        rose = new Rose{salt: "REDROSE", value: liquidityInit}(1e5, 1e4, liquidityInit, address(this), 1e25);
    }

    function test_approve(address to, uint value) public {
        assertEq(rose.allowance(address(this), to), 0);

        assertTrue(rose.approve(to, value));

        assertEq(rose.allowance(address(this), to), value);
    }

    function test_transfer(address to, uint value) public {
        vm.assume(to != address(this));
        vm.assume(to != address(rose));
        vm.assume(value <= type(uint).max - rose.balanceOf(to));
        uint selfInitialRoseBalance = rose.balanceOf(address(this));
        uint toInitialRoseBalance = rose.balanceOf(to);

        rose.mint(address(this), value);

        assertTrue(rose.transfer(to, value));

        assertEq(rose.balanceOf(address(this)), 0);
        assertEq(rose.balanceOf(to), toInitialRoseBalance + value);
    }

    function testFail_transferNotEnoughBalance(address to, uint balance, uint value) public {
        vm.assume(value > balance);
        rose.mint(address(this), balance);
        
        assertTrue(rose.transfer(to, value));
    }


    function test_transferFrom(address from, address to, uint value) public {
        vm.assume(address(this) != from);
        vm.assume(from != to);
        uint toInitialRoseBalance = rose.balanceOf(to);

        rose.mint(from, value);

        vm.startPrank(from);
        assertTrue(rose.approve(address(this), value));
        vm.stopPrank();
        
        assertTrue(rose.allowance(from, address(this)) == value);

        assertTrue(rose.transferFrom(from, to, value));

        assertEq(rose.balanceOf(from), 0);
        assertEq(rose.balanceOf(to), toInitialRoseBalance + value);
    }

    function testFail_transferFromNotEnoughAllowance(address from, address to, uint allowance, uint value) public {
        vm.assume(value > 0);
        vm.assume(allowance < value);
        rose.mint(from, value);
        
        vm.startPrank(from);
        rose.approve(address(this), allowance);
        vm.stopPrank();

        assertTrue(rose.transferFrom(from, to, value));
    }

    function testFail_transferFromNotEnoughBalance(address from, address to, uint balance, uint value) public {
        vm.assume(from != address(rose));
        vm.assume(value > balance);
        rose.mint(from, balance);

        vm.startPrank(from);
        rose.approve(address(this), value);
        vm.stopPrank();
        
        assertTrue(rose.transferFrom(from, to, value));
    }

    function test_buy(uint value) public {
        vm.assume(value < address(this).balance);
        (uint r0, uint r1, uint alpha) = rose.getState();
        uint selfInitialRoseBalance = rose.balanceOf(address(this));
        uint selfInitialWethBalance = address(this).balance;
        uint quote = rose.quoteDeposit(value);

        uint out = rose.deposit{value: value}(quote);
        assertEq(quote, out);

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

    function test_sell(uint value) public {
        vm.assume(value <= rose.balanceOf(address(rose)) / 50);
        rose.mint(address(this), value);
        uint selfInitialRoseBalance = rose.balanceOf(address(this));
        uint selfInitialWethBalance = address(this).balance;
        (uint r0, uint r1, uint alpha) = rose.getState();
        uint quote = rose.quoteWithdraw(value);

        uint out = rose.withdraw(value, quote);
        assertEq(quote, out);

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

    function test_collect(uint value) public {
        vm.assume(value <= rose.balanceOf(address(rose)) / 50);
        rose.mint(address(this), value);
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

    receive() external payable {}
}
