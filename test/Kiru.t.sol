// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Kiru} from "../src/Kiru.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KiruTest is Test {

    Kiru public kiru;
    uint256 public constant R0_INIT = 2e18;
    uint256 public constant ALPHA = 1e3;
    uint256 public constant PHI = 1e4;
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant R1_INIT = 850_000_000 * 1e18;
    uint256 public constant TREASURY_ALLOCATION = 90_000_000 * 1e18;
    uint256 public constant CLAWBACK = 60_000_000 * 1e18;
    address public constant TREASURY = address(0x3);

    function setUp() public {
        kiru = new Kiru{salt: "REDKIRU", value: R0_INIT}(
            ALPHA, 
            PHI, 
            R1_INIT, 
            SUPPLY,
            TREASURY
        );
    }

    function test_alpha(uint[100] memory amounts) public {
        vm.deal(address(this), type(uint).max);
        for (uint i=0; i<amounts.length; i++) {
            amounts[i] = bound(amounts[i], 1e6, 1e18);
        }
        uint oldKiruBalance;
        uint oldEthBalance;

        uint withdrawAmount;
        uint r1;
        uint r1_5Percent;
        uint totalBuys;
        uint totalSells;
        for (uint i=0; i<amounts.length; i++) {
            if (i % 2 == 0) {
                kiru.deposit{value: amounts[i]}(0);
                oldKiruBalance = kiru.balanceOf(address(this));
                (, r1,) = kiru.getState();
                totalBuys += amounts[i];
            } else {
                r1_5Percent = r1 / 5;
                
                withdrawAmount = amounts[i] > kiru.balanceOf(address(this)) ? kiru.balanceOf(address(this)) : amounts[i];
                if (r1_5Percent < withdrawAmount) {
                    kiru.withdraw(r1_5Percent, 0);
                } else {
                    kiru.withdraw(withdrawAmount, 0);
                }
            }
        }
        (uint r0, uint _r1, uint alpha) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", _r1);
        emit log_named_uint("alpha", alpha);
        emit log_named_uint("mc", (r0 * 1e6 / _r1) * kiru.totalSupply() / 1e6 / 1e18);
    }

    // function test_alpha(uint[100] memory amounts) public {
    //     vm.deal(address(this), type(uint).max);
    //     uint amount;
    //     uint oldKiruBalance;
    //     uint oldEthBalance;
    //     uint withdrawAmount;
    //     uint r1;
    //     uint r1_5Percent;
    //     bool withdrawLoop = true;
    //     for (uint i = 0; i < amounts.length; i++) {
    //         amount = amounts[i];
    //         oldKiruBalance = kiru.balanceOf(address(this));
    //         kiru.deposit{value: amount}(0);
    //         withdrawAmount = kiru.balanceOf(address(this)) - oldKiruBalance;
    //         emit log_named_uint("withdraw amount", withdrawAmount);
    //         oldEthBalance = address(this).balance;
    //         while (withdrawLoop) {
    //             (, r1,) = kiru.getState();
    //             r1_5Percent = r1 / 5 - 1;
    //             if (r1_5Percent > withdrawAmount) {
    //                 kiru.withdraw(r1_5Percent, 0);
    //                 withdrawAmount -= r1_5Percent;
    //             } else {
    //                 kiru.withdraw(withdrawAmount, 0);
    //                 withdrawLoop = false;
    //             }
    //         }
    //         emit log_named_uint("eth balance increase", address(this).balance - oldEthBalance);
    //     }
    //     (uint r0, uint _r1, uint alpha) = kiru.getState();
    //     emit log_named_uint("r0", r0);
    //     emit log_named_uint("r1", _r1);
    //     emit log_named_uint("alpha", alpha);
    // }

    function test_withdrawalReserves() public {
        (uint r0, uint r1,) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", r1);
        mint(address(this), 1000000e18);
        uint quote = kiru.quoteWithdraw(1000e18);
        kiru.withdraw(1000e18, quote);
        (uint r0_cp, uint r1_cp) = sell_cp(r0, r1, 1000e18);
        emit log_named_uint("r0_cp", r0_cp);
        emit log_named_uint("r1_cp", r1_cp);
        (r0, r1,) = kiru.getState();
        emit log_named_uint("r0Prime", r0);
        emit log_named_uint("r1Prime", r1);
        assertEq(r0, r0_cp);
        assertEq(r1, r1_cp);
    }

    function test_getState() public {
        (uint r0, uint r1, uint alpha) = kiru.getState();
        emit log_named_uint("r0", r0);
        emit log_named_uint("r1", r1);
        emit log_named_uint("alpha", alpha);
    }

    function test_corner() public {
        // Checks if the deposit function works correctly
        // Verifies token balances, ETH balances, and contract state after a purchase
        emit log("--------------------------------");
        emit log("before corner");
        emit log("--------------------------------");
        (uint r0, uint r1, uint alpha) = kiru.getState();
        uint selfInitialKiruBalance = kiru.balanceOf(address(this));

        emit log_named_uint("spot price", spotPrice());
        emit log_named_uint("total supply", kiru.totalSupply());
        emit log_named_uint("mc", spotPrice() * kiru.totalSupply() / 1e18);

        for (uint i = 0; i < 21; i++) {
            kiru.deposit{value: 1e17}(0);
        }
        emit log("--------------------------------");
        emit log("after corner");
        emit log("--------------------------------");
        (uint r0Prime, uint r1Prime, uint alphaPrime) = kiru.getState();

        uint selfKiruBalanceAfterBuys = kiru.balanceOf(address(this));
        emit log_named_uint("r0Prime", r0Prime);
        emit log_named_uint("r1Prime", r1Prime);
        emit log_named_uint("alphaPrime", alphaPrime);
        emit log_named_uint("Kiru balance increase", selfKiruBalanceAfterBuys - selfInitialKiruBalance);
        emit log_named_uint("spot price", spotPrice());
        emit log_named_uint("total supply", kiru.totalSupply());
        emit log_named_uint("mc", spotPrice() * kiru.totalSupply() / 1e18);

        kiru.deposit{value: 4e17}(0);
        emit log("--------------------------------");
        emit log("after jouloud");
        emit log("--------------------------------");
        (r0Prime, r1Prime, alphaPrime) = kiru.getState();
        emit log_named_uint("alphaPrime", alphaPrime);
        uint selfKiruBalanceAfterJouloud = kiru.balanceOf(address(this));
        uint balanceIncreaseAfterJouloud = selfKiruBalanceAfterJouloud - selfInitialKiruBalance - (selfKiruBalanceAfterBuys - selfInitialKiruBalance);
        emit log_named_uint("Kiru balance increase", balanceIncreaseAfterJouloud);
        emit log_named_uint("spot price", spotPrice());
        emit log_named_uint("total supply", kiru.totalSupply());
        emit log_named_uint("mc", spotPrice() * kiru.totalSupply());

        for (uint i = 0; i < 30; i++) {
            kiru.deposit{value: 4e18}(0);
            kiru.withdraw(1e18, 0);
        }

        emit log("--------------------------------");
        emit log("after volume");
        emit log("--------------------------------");
        (r0Prime, r1Prime, alphaPrime) = kiru.getState();
        emit log_named_uint("r0Prime", r0Prime);
        emit log_named_uint("r1Prime", r1Prime);
        emit log_named_uint("alphaPrime", alphaPrime);
        uint selfKiruBalanceAfterVolume = kiru.balanceOf(address(this));
        uint balanceIncreaseAfterVolume = selfKiruBalanceAfterVolume - selfInitialKiruBalance - balanceIncreaseAfterJouloud;
        emit log_named_uint("Kiru balance increase", balanceIncreaseAfterVolume);
        emit log_named_uint("spot price", spotPrice());
        emit log_named_uint("total supply", kiru.totalSupply());
        emit log_named_uint("mc", spotPrice() * kiru.totalSupply() / 1e18);

        assert(false);
    }

    function test_single_corner() public {
        // Checks if the deposit function works correctly
        // Verifies token balances, ETH balances, and contract state after a purchase
        (uint r0, uint r1, uint alpha) = kiru.getState();
        uint selfInitialKiruBalance = kiru.balanceOf(address(this));
        uint quote = kiru.quoteDeposit(1e18);

        kiru.deposit{value: 2e18}(quote);

        (uint r0Prime, uint r1Prime, uint alphaPrime) = kiru.getState();
        emit log_named_uint("r0Prime", r0Prime);
        emit log_named_uint("r1Prime", r1Prime);
        emit log_named_uint("alphaPrime", alphaPrime);
        emit log_named_uint("Kiru balance increase", kiru.balanceOf(address(this)) - selfInitialKiruBalance);
        emit log_named_uint("spot price", spotPrice());
        emit log_named_uint("total supply", kiru.totalSupply());
        assert(false);
    }

    // Test the approve function
    function testApprove(address to, uint value) public {
        // Checks if the approval mechanism works correctly
        // Verifies initial allowance is 0, then approves a value, and confirms the new allowance
        assertEq(kiru.allowance(address(this), to), 0);

        assertTrue(kiru.approve(to, value));

        assertEq(kiru.allowance(address(this), to), value);
    }

    // Test the transfer function
    function testTransfer(address from, address to, uint value) public {
        // Ensures the transfer function works as expected
        // Mints tokens, transfers them, and verifies balances are updated correctly
        vm.assume(to != address(this));
        vm.assume(from != address(kiru));
        vm.assume(from != to);
        vm.assume(from != address(this));
        vm.assume(from != TREASURY);

        mint(from, value);

        uint selfInitialKiruBalance = kiru.balanceOf(from);
        uint toInitialKiruBalance = kiru.balanceOf(to);

        vm.prank(from);
        kiru.transfer(to, value);

        assertEq(kiru.balanceOf(from), selfInitialKiruBalance - value);
        assertEq(kiru.balanceOf(to), toInitialKiruBalance + value);
    }

    // Test transfer failure due to insufficient balance
    function testTransferNotEnoughBalance(address from,address to, uint balance, uint value) public {
        // Verifies that a transfer fails when the sender doesn't have enough balance
        vm.assume(from != address(kiru));
        vm.assume(from != to);
        vm.assume(from != address(this));
        vm.assume(value > balance);
        vm.assume(from != TREASURY);

        mint(from, balance);

        vm.prank(from);
        vm.expectRevert();
        kiru.transfer(to, value);
    }


    // Test the transferFrom function
    function testTransferFrom(address from, address to, uint value) public {
        // Checks if transferFrom works correctly
        // Mints tokens, approves spending, transfers tokens, and verifies balances
        vm.assume(address(this) != from);
        vm.assume(from != to);
        vm.assume(to != address(kiru));
        vm.assume(from != TREASURY);

        mint(from, value);

        uint fromInitialKiruBalance = kiru.balanceOf(from);
        uint toInitialKiruBalance = kiru.balanceOf(to);

        vm.prank(from);
        kiru.approve(to, value);
        
        vm.prank(to);
        kiru.transferFrom(from, to, value);

        assertEq(kiru.balanceOf(from), fromInitialKiruBalance - value);
        assertEq(kiru.balanceOf(to), toInitialKiruBalance + value);
    }

    // Test transferFrom failure due to insufficient allowance
    function testFailTransferFromNotEnoughAllowance(address from, address to, uint allowance, uint value) public {
        // Ensures transferFrom fails when the spender doesn't have enough allowance
        vm.assume(value > 0);
        vm.assume(allowance < value);
        mint(from, value);
        
        vm.startPrank(from);
        kiru.approve(address(this), allowance);
        vm.stopPrank();

        assertTrue(kiru.transferFrom(from, to, value));
    }

    // Test transferFrom failure due to insufficient balance
    function testTransferFromNotEnoughBalance(address from, address to, uint balance, uint value) public {
        // Verifies that transferFrom fails when the sender doesn't have enough balance
        vm.assume(from != address(kiru));
        vm.assume(from != to);
        vm.assume(from != address(this));
        vm.assume(value > balance);
        vm.assume(from != TREASURY);

        mint(from, balance);

        vm.startPrank(from);
        kiru.approve(to, value);
        vm.stopPrank();
        
        vm.prank(to);
        vm.expectRevert();
        kiru.transferFrom(from, to, value);
    }

    // Test the buy (deposit) function
    function testBuy(uint value) public {
        // Checks if the deposit function works correctly
        // Verifies token balances, ETH balances, and contract state after a purchase
        vm.deal(address(this), 1000 ether);
        (uint initialR0, uint initialR1, ) = kiru.getState();
        uint _out = buy(initialR0);
        assertGe(_out, initialR0 / 2);
        vm.assume(value < address(this).balance);
        (uint r0, uint r1, uint alpha) = kiru.getState();
        uint selfInitialKiruBalance = kiru.balanceOf(address(this));
        uint selfInitialWethBalance = address(this).balance;
        uint quote = kiru.quoteDeposit(value);

        kiru.deposit{value: value}(quote);
        
        // assertEq(quote, out);

        (uint r0Prime, uint r1Prime, uint alphaPrime) = kiru.getState();
        assertEq(address(this).balance, selfInitialWethBalance - value);
        assertLe(kiru.balanceOf(address(kiru)), r1);
        assertGe(address(kiru).balance, r0);
        assertGe(kiru.balanceOf(address(this)), selfInitialKiruBalance);
        assertEq(r0Prime, address(kiru).balance);
        assertEq(r1Prime, kiru.balanceOf(address(kiru)));
        assertEq(r0Prime, r0 + value);
        assertGe(r0Prime, r0);
        assertLe(r1Prime, r1);
        emit log_named_uint("mc", spotPrice() * kiru.totalSupply() / 1e18);
        assertGe(alphaPrime, alpha);
        if (r1 > 0 && r1Prime > 0) {
            assertGe(r0Prime * 1e6 / r1Prime, r0 * 1e6 / r1);
        }
    }

    // Test the sell (withdraw) function
    function testSell(uint value) public {
        // Ensures the withdraw function works as expected
        // Verifies token balances, ETH balances, and contract state after a sale
        vm.assume(value <= kiru.balanceOf(address(kiru)) / 5);
        mint(address(this), value);
        uint selfInitialKiruBalance = kiru.balanceOf(address(this));
        uint selfInitialWethBalance = address(this).balance;
        (uint r0, uint r1, uint alpha) = kiru.getState();
        uint quote = kiru.quoteWithdraw(value);

        kiru.withdraw(value, quote);
        // assertEq(quote, out);

        (uint r0Prime, uint r1Prime, uint alphaPrime) = kiru.getState();
        uint fees = address(kiru).balance - r0Prime;
        assertEq(address(kiru).balance, r0Prime + fees);
        assertEq(kiru.balanceOf(address(kiru)), r1Prime);
        assertEq(kiru.balanceOf(address(this)), selfInitialKiruBalance - value);
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
        vm.assume(value <= kiru.balanceOf(address(kiru)) / 50);
        mint(address(this), value);
        assertEq(kiru.balanceOf(address(this)), value);
        uint treasuryInitialWethBalance = address(kiru.TREASURY()).balance;
        uint kiruInitialWethBalance = address(kiru).balance;
        
        assertTrue(kiru.transfer(address(kiru), value));

        (uint r0, uint r1, uint alpha) = kiru.getState();
        uint fees = address(kiru).balance - r0;

        vm.startPrank(kiru.TREASURY());
        kiru.collect();
        vm.stopPrank();

        assertEq(kiruInitialWethBalance, address(kiru).balance + fees);
        assertEq(treasuryInitialWethBalance + fees, address(kiru.TREASURY()).balance);
    }

    function test_instantArbitrageSimple(uint valueIn, uint valueOut) public {
        emit log_named_uint("valueIn", valueIn);
        emit log_named_uint("valueOut", valueOut);
        vm.assume(valueIn <= address(this).balance);
        uint oldKiruBalance = kiru.balanceOf(address(this));
        uint balanceBeforeDeposit = address(this).balance;
        emit log_named_uint("balanceBeforeDeposit", balanceBeforeDeposit);
        uint quote = kiru.quoteDeposit(valueIn);
        emit log_named_uint("quote", quote);
        kiru.deposit{value: valueIn}(quote);
        uint deltaY = kiru.balanceOf(address(this)) - oldKiruBalance;
        emit log_named_uint("deltaY", deltaY);
        assertEq(deltaY, quote);
        vm.assume(valueOut < deltaY);
        (, uint r1,) = kiru.getState();
        emit log_named_uint("r1", r1);
        vm.assume(valueOut <= r1 / 5);
        uint quoteOut = kiru.quoteWithdraw(valueOut);
        emit log_named_uint("quoteOut", quoteOut);
        uint balanceBeforeWithdraw = address(this).balance;
        emit log_named_uint("balanceBeforeWithdraw", balanceBeforeWithdraw);
        kiru.withdraw(valueOut, quoteOut);
        emit log_named_uint("newBalance", address(this).balance);
        uint deltaX = address(this).balance - balanceBeforeWithdraw;
        assertEq(deltaX, quoteOut);
        assertLe(address(this).balance, balanceBeforeDeposit);
    }

    function test_priceAction(uint valueIn, uint valueOut) public {
        // buy half of kiru reserves to unlock the alpha scaling
        vm.deal(address(this), 1000 ether);
        (uint initialR0, uint initialR1, ) = kiru.getState();
        uint _out = buy(initialR0);
        assertGe(_out, initialR0 / 2);
        (uint r0, uint r1,) = kiru.getState();
        emit log("--------------------------------");
        emit log("initial reserves");
        emit log("--------------------------------");
        emit log_named_uint("initial r0", r0);
        emit log_named_uint("initial r1", r1);
        emit log("");
        emit log("--------------------------------");
        emit log("initial spot price");
        emit log("--------------------------------");
        uint initialSpotPrice = spotPrice();
        emit log_named_uint("initial spot price", initialSpotPrice);
        emit log("");
        uint valueIn = bound(valueIn, 1e12, address(this).balance);
        (uint aR0Prime, uint aR1Prime) = buy_a(valueIn);
        (uint cpR0Prime, uint cpR1Prime) = buy_cp(valueIn);
        uint deltaY = buy(valueIn);

        (uint r0Prime, uint r1Prime,) = kiru.getState();
        uint spotAfterBuy = spotPrice();
        uint aSpotAfterBuy = spotPrice(aR0Prime, aR1Prime);
        uint cpSpotAfterBuy = spotPrice(cpR0Prime, cpR1Prime);
        emit log("--------------------------------");
        emit log("spot price after buy");
        emit log("--------------------------------");
        emit log_named_uint("spot after buy", spotAfterBuy);
        emit log_named_uint("a spot after buy", aSpotAfterBuy);
        emit log_named_uint("cp spot after buy", cpSpotAfterBuy);
        emit log("");
        assertEq(spotAfterBuy, aSpotAfterBuy);
        assertGt(spotAfterBuy, cpSpotAfterBuy);

        uint valueOut = bound(valueOut, 1e18, kiru.balanceOf(address(this)));
        valueOut = valueOut > r1Prime / 5 ? r1Prime / 5 : valueOut;

        uint balanceBeforeSell = address(this).balance;
        sell(valueOut);
        uint deltaX = address(this).balance - balanceBeforeSell;
        emit log_named_uint("deltaX", deltaX);
        (cpR0Prime, cpR1Prime) = sell_cp(cpR0Prime, cpR1Prime, valueOut);
        (uint cpR0Prime2, uint cpR1Prime2) = sell_cp(r0Prime, r1Prime, valueOut);

        uint spotAfterSell = spotPrice();
        uint cpSpotAfterSell = spotPrice(cpR0Prime, cpR1Prime); 
        uint cpSpotAfterSellKiruReserves = spotPrice(cpR0Prime2, cpR1Prime2);
        emit log("--------------------------------");
        emit log("spot price after sell");
        emit log("--------------------------------");
        emit log_named_uint("spot after sell", spotAfterSell);
        emit log_named_uint("cp spot after sell", cpSpotAfterSell);
        emit log_named_uint("cp spot after sell 2", cpSpotAfterSellKiruReserves);
        assertEq(spotAfterSell, cpSpotAfterSellKiruReserves);
        assertGt(spotAfterSell, cpSpotAfterSell);
        // assertGt(spotAfterSell, initialSpotPrice);
    }

    function test_threshold0(uint _in) public {
        vm.deal(address(this), 1000 ether);
        vm.assume(_in < address(this).balance);
        (uint initialR0, uint initialR1, uint initialAlpha) = kiru.getState();
        uint _out = buy(_in);
        (uint r0Prime, uint r1Prime, uint alphaPrime) = kiru.getState();
        vm.assume(r1Prime > initialR1 / 2);
        assertEq(alphaPrime, initialAlpha);
        assertEq(r0Prime, initialR0 + _in);
        // assertEq(r1Prime, initialR1 - _out);
    }

    function test_threshold1(uint _in) public {
        vm.deal(address(this), 1000 ether);
        (uint initialR0, uint initialR1, uint initialAlpha) = kiru.getState();
        uint _in = bound(_in, initialR0, 1000 ether);
        uint _out = buy(_in);
        (uint r0Prime, uint r1Prime, uint alphaPrime) = kiru.getState();
        // vm.assume(r1Prime < initialR1 / 2);
        assertGt(initialAlpha, alphaPrime);
        assertEq(r0Prime, initialR0 + _in);
        // assertEq(r1Prime, initialR1 - _out);
    }

    function spotPrice() internal view returns (uint) {
        (uint r0, uint r1,) = kiru.getState();
        return r0 * 1e18 / r1;
    }

    function spotPrice(uint r0, uint r1) internal view returns (uint) {
        return r0 * 1e18 / r1;
    }

    function mint(address to, uint value) internal {
        bytes32 TO_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, to)
            mstore(add(ptr, 0x20), 0)
            TO_BALANCE_SLOT := keccak256(ptr, 0x40)
        }
        vm.store(address(kiru), TO_BALANCE_SLOT, bytes32(value));
    }

    function buy(uint value) internal returns (uint deltaY) {
        uint oldKiruBalance = kiru.balanceOf(address(this));
        uint quote = kiru.quoteDeposit(value);
        kiru.deposit{value: value}(quote);
        deltaY = kiru.balanceOf(address(this)) - oldKiruBalance;
        assertEq(deltaY, quote);
        emit log("");
        emit log("--------------------------------");
        emit log("BUY EVENT");
        emit log("--------------------------------");
        emit log_named_uint("buy amount in:", value);
        emit log_named_uint("buy amount out:", deltaY);
        (uint r0, uint r1,) = kiru.getState();
        emit log_named_uint("new r0:", r0);
        emit log_named_uint("new r1:", r1);
        emit log("");
    }

    function buy_cp(uint value) internal returns (uint r0Prime, uint r1Prime) {
        (uint r0, uint r1,) = kiru.getState();
        r0Prime = r0 + value;
        r1Prime = r0 * r1 / r0Prime;
        emit log("");
        emit log("--------------------------------");
        emit log("BUY_CP EVENT");
        emit log("--------------------------------");
        emit log_named_uint("buy_cp r0Prime", r0Prime);
        emit log_named_uint("buy_cp r1Prime", r1Prime);
        emit log_named_uint("buy_cp y", r1 - r1Prime);
        emit log("");
    }

    function buy_a(uint value) internal returns (uint r0Prime, uint r1Prime) {
        (uint r0, uint r1, uint alpha) = kiru.getState();
        uint aR0 = r0 * alpha / 1e6;
        uint aR1 = r1 * alpha / 1e6;
        emit log("");
        emit log("--------------------------------");
        emit log("BUY_A EVENT");
        emit log("--------------------------------");
        emit log_named_uint("buy_a alpha", alpha);
        emit log_named_uint("buy_a aR0", aR0);
        emit log_named_uint("buy_a aR1", aR1);

        uint aR0Prime = aR0 + value;
        uint aR1Prime = aR0 * aR1 / aR0Prime;
        uint aRatio = aR1Prime * 1e6 / aR0Prime;
        emit log_named_uint("buy_a aR0Prime", aR0Prime);
        emit log_named_uint("buy_a aR1Prime", aR1Prime);

        r0Prime = r0 + value;
        r1Prime = aRatio * r0Prime / 1e6;
        emit log_named_uint("buy_a r0Prime", r0Prime);
        emit log_named_uint("buy_a r1Prime", r1Prime);
        emit log("");
    }

    function sell(uint value) internal returns (uint deltaX) {
        (, uint r1,) = kiru.getState();
        vm.assume(value <= r1 / 5);
        uint oldEthBalance = address(this).balance;
        uint quote = kiru.quoteWithdraw(value);
        kiru.withdraw(value, quote);
        deltaX = address(this).balance - oldEthBalance;
        assertEq(deltaX, quote);
        emit log("--------------------------------");
        emit log("SELL EVENT");
        emit log("--------------------------------");
        emit log_named_uint("sell amount in:", value);
        emit log_named_uint("sell amount out:", deltaX);
        (uint r0Prime, uint r1Prime,) = kiru.getState();
        emit log_named_uint("new r0:", r0Prime);
        emit log_named_uint("new r1:", r1Prime);
    }

    function sell_cp(uint r0, uint r1, uint value) internal returns (uint r0Prime, uint r1Prime) {
        r1Prime = r1 + value;
        r0Prime = (r0 * r1) / (r1+value);
    }

    receive() external payable {}
}
