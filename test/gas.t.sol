// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Rose} from "../src/Rose.sol";

contract GasTest is Test {

    Rose public rose;
    uint public liquidityInit = 1e24;

    function setUp() public {
        rose = new Rose{salt: "REDROSE", value: liquidityInit}(1e5, 1e4, liquidityInit, address(this));
    }

    function test_approve(address to, uint value) public {
        rose.approve(to, value);
    }

    function test_transfer(address to, uint value) public {
        vm.assume(to != address(this));
        vm.assume(to != address(rose));
        rose.mint(address(this), value);
        rose.transfer(to, value);
    }

    function test_transferFrom(address from, address to, uint value) public {
        vm.assume(address(this) != from);
        vm.assume(from != to);
        vm.assume(to != address(rose));
        rose.mint(from, value);
        vm.startPrank(from);
        rose.approve(address(this), value);
        vm.stopPrank();
        rose.transferFrom(from, to, value);
    }

    function test_buy(uint value) public {
        vm.assume(value < address(this).balance);
        rose.deposit{value: value}(0);
    }

    function test_sell(uint value) public {
        vm.assume(value <= rose.balanceOf(address(rose)) / 50);
        rose.mint(address(this), value);
        rose.withdraw(value, 0);
    }

    function test_collect() public {
        rose.collect();
    }

    receive() external payable {}
}
