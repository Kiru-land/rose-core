// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Rose} from "../src/Rose.sol";

contract GasTest is Test {

    Rose public rose;
    uint public liquidityInit = 1e24;

    function setUp() public {
        rose = new Rose{salt: "REDROSE", value: liquidityInit}(1e5, 1e4, liquidityInit, address(this), 1e25);
    }

    function test_approve(address to, uint value) public {
        rose.approve(to, value);
    }

    function test_transfer(address to, uint value) public {
        vm.assume(to != address(this));
        vm.assume(to != address(rose));
        mint(address(this), value);
        rose.transfer(to, value);
    }

    function test_transferFrom(address from, address to, uint value) public {
        vm.assume(address(this) != from);
        vm.assume(from != to);
        vm.assume(to != address(rose));
        mint(from, value);
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
        mint(address(this), value);
        rose.withdraw(value, 0);
    }

    function test_collect() public {
        rose.collect();
    }

    function mint(address to, uint value) internal {
        bytes32 CALLER_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 0)
            CALLER_BALANCE_SLOT := keccak256(ptr, 0x40)
        }
        vm.store(address(rose), CALLER_BALANCE_SLOT, bytes32(value));
    }

    receive() external payable {}
}
