// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EvilKiru} from "../src/EvilKiru.sol";

interface IERC20 {
    function transfer(address, uint) external;
    function balanceOf(address) external view returns (uint);
}

interface IKiru {
    function deposit(uint) external payable;
    function withdraw(uint, uint) external;
    function quoteDeposit(uint) external view returns (uint);
    function getState() external view returns (uint, uint, uint);
}

contract EvilKiruTest is Test {

    EvilKiru public riku;
    address treasury = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;
    IERC20 public kiru = IERC20(0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2);

    function setUp() public {
        uint256 seedAmount = 3_000_000_000e18;
        uint256 supply = 1_000_000_000_000e18;
        uint256 _alpha = 1e3;
        vm.prank(treasury);
        kiru.transfer(address(this), seedAmount);
        riku = new EvilKiru(_alpha, supply);
        kiru.transfer(address(riku), seedAmount);
    }

    // ensure less eth when roundtrip
    // ensure price higher or equal
    function test_deposit(uint value) public {
        vm.deal(address(this), 1_000_000_000_000e18);
        value = bound(value, 1, 1_000_000_000_000e18);

        uint256 kiruEthBalanceBefore = address(kiru).balance;
        uint256 rikuBalanceBefore = IERC20(address(riku)).balanceOf(address(this));
        uint256 rikuKiruBalanceBefore = IERC20(address(kiru)).balanceOf(address(riku));
        (uint r0, uint r1, ) = IKiru(address(kiru)).getState();
        uint256 kiruPriceInEthBefore = r0 * 1e18 / r1;

        // deposit
        riku.deposit{value: value}(0, 0);

        (uint r0After, uint r1After, ) = IKiru(address(kiru)).getState();
        uint256 kiruPriceInEthAfter = r0After * 1e18 / r1After;

        // asserts there are more ETH on the kiru contract than before
        assertEq(address(kiru).balance, kiruEthBalanceBefore + value);
        // asserts caller received riku tokens
        assertGt(IERC20(address(riku)).balanceOf(address(this)), rikuBalanceBefore);
        // asserts riku has more Kiru than before
        assertGt(IERC20(address(kiru)).balanceOf(address(riku)), rikuKiruBalanceBefore);
        // asserts kiru price is higher or equal
        assertGe(kiruPriceInEthAfter, kiruPriceInEthBefore);
    }

    function test_roundtrip(uint value) public {
        vm.deal(address(this), 1_000_000_000_000e18);
        value = bound(value, 1, 1e18);

        // deposit
        riku.deposit{value: value}(0, 0);

        // withdraw
        uint256 ethBalanceBefore = address(this).balance;

        uint256 rikuBalance = IERC20(address(riku)).balanceOf(address(this));

        riku.withdraw(rikuBalance, 0, 0);
        uint256 ethReceived = address(this).balance - ethBalanceBefore;
        // asserts caller gets less eth than deposited
        assertGe(value, ethReceived);
    }

    // asserts quote is equal to amount received
    function test_quoteDeposit(uint256 value) public {
        vm.deal(address(this), 1_000_000_000_000e18);
        value = bound(value, 1, 1_000_000_000_000e18);

        // quote deposit
        (uint256 quote,) = riku.quoteDeposit(value);
        uint256 rikuBalanceBefore = IERC20(address(riku)).balanceOf(address(this));

        // deposit
        riku.deposit{value: value}(0, 0);

        uint256 rikuBalanceAfter = IERC20(address(riku)).balanceOf(address(this));
        uint256 rikuReceived = rikuBalanceAfter - rikuBalanceBefore;
        assertGe(rikuReceived, quote);
    }


    function test_withdraw(uint256 value) public {
        vm.deal(address(this), 1_000_000_000_000e18);
        value = bound(value, 1, 1e18);

        // deposit
        riku.deposit{value: value}(0, 0);

        // withdraw
        uint256 ethBalanceBefore = address(this).balance;
        uint256 rikuBalance = IERC20(address(riku)).balanceOf(address(this));
        riku.withdraw(rikuBalance, 0, 0);

        uint256 ethReceived = address(this).balance - ethBalanceBefore;

        // assert caller get eth back
        assertGt(ethReceived, 0);
    }

    function test_quoteWithdraw(uint256 value) public {
        vm.deal(address(this), 1_000_000_000_000e18);
        value = bound(value, 1, 1e18);

        // deposit
        riku.deposit{value: value}(0, 0);

        // withdraw
        uint256 ethBalanceBefore = address(this).balance;
        uint256 rikuBalance = IERC20(address(riku)).balanceOf(address(this));
        (uint quote,) = riku.quoteWithdraw(rikuBalance);

        riku.withdraw(rikuBalance, 0, 0);
        uint256 ethReceived = address(this).balance - ethBalanceBefore;
        assertGe(ethReceived, quote);
    }

    receive() external payable {}
}
