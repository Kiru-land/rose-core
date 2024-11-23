// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Kiru} from "../src/Kiru.sol";
import {Deposit2} from "../src/Deposit2.sol";

contract Deposit2Test is Test {

    Kiru public kiru = Kiru(payable(0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2));
    Deposit2 public deposit2;

    function setUp() public {
        deposit2 = new Deposit2(100);
    }

    function test_deposit(uint value) public {
        vm.assume(value <= address(this).balance);
        vm.assume(value > 1e4);

        uint balanceBefore = kiru.balanceOf(address(this));
        uint balanceZeroBefore = kiru.balanceOf(address(0));

        uint quote = deposit2.quoteDeposit(value);

        (uint r0, uint r1, uint alpha) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", r1);
        emit log_named_uint("alpha", alpha);
        uint ratioBefore = r0 * 1e18 / r1;
        emit log_named_uint("ratioBefore", ratioBefore);
        
        deposit2.deposit{value: value}(quote);

        uint balanceAfter = kiru.balanceOf(address(this));

        uint out = balanceAfter - balanceBefore;

        emit log_named_uint("out", out);
        assertEq(out, quote);

        (r0, r1, alpha) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", r1);
        emit log_named_uint("alpha", alpha);
        uint ratioAfter = r0 * 1e18 / r1;
        emit log_named_uint("ratioAfter", ratioAfter);
        assert(ratioAfter >= ratioBefore);
        assert(balanceAfter >= balanceBefore);
        assert(kiru.balanceOf(address(0)) >= balanceZeroBefore);
    }

    function test_state(uint value) public {
        vm.assume(value <= address(this).balance);
        vm.assume(value > 1);

        (uint r0, uint r1, uint alpha) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", r1);
        emit log_named_uint("alpha", alpha);
        uint oldR0 = r0;
        uint oldR1 = r1;

        address(kiru).call{value: value}("");

        (r0, r1, alpha) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", r1);
        emit log_named_uint("alpha", alpha);

        assertEq(r0, oldR0 + value);
        assertEq(r1, oldR1);
    }
}
