// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Rose} from "../src/Rose.sol";

contract GasTest is Test {

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
            FOR_SALE, 
            TREASURY_ALLOCATION, 
            CLAWBACK,
            TREASURY
        );
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
