// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Bond} from "../src/Bond.sol";
import {Kiru} from "../src/Kiru.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3PoolState} from "../src/interfaces/IUniswapV3PoolState.sol";

// Mock contracts for testing
contract BondTest is Test {
    Bond public bond;
    address payable kiru = payable(0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2);
    
    // Constants
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint24 constant POOL_FEE = 10000; // 1%
    int24 constant MIN_TICK = -887200;
    int24 constant MAX_TICK = 887200;
    address TREASURY = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    function setUp() public {
        // Deploy mock Kiru token
        // kiru = new Kiru{value: 10e18}(
        //     10e4,
        //     10e5,
        //     850000000000000000000000000000,
        //     1000000000000000000000000000000,
        //     TREASURY
        //     );
        // Deploy Bond contract
        bond = new Bond(address(kiru));
        // Transfer some Kiru tokens to Bond contract for rewards
        vm.deal(address(this), 100_000 * 1e18);
        vm.prank(TREASURY);
        Kiru(kiru).transfer(address(bond), 75000000000000000000000000000);
    }

    // function test_kiru() public {
    //     uint a = 1+1;
    // }

    function testBond() public {

        // Setup test values
        uint ethAmount = 0.001 ether;
        uint outMin = 0;
        uint amount0Min = 0;
        uint amount1Min = 0;

        // Execute bond function
        bond.bond{value: ethAmount}(outMin, amount0Min, amount1Min);

        // // Verify results
        // assertTrue(kiru.balanceOf(address(this)) > initialKiruBalance, "Should receive Kiru tokens");
        // assertTrue(address(this).balance < initialEthBalance, "Should spend ETH");
    }

    // function testBondWithZeroEth() public {
    //     // Should revert when trying to bond with 0 ETH
    //     vm.expectRevert("No ETH sent");
    //     bond.bond(0, 0, 0);
    // }

    // function testBondWithInsufficientRewards() public {
    //     // Drain bond contract of rewards
    //     vm.prank(address(bond));
    //     kiru.transfer(address(0), kiru.balanceOf(address(bond)));

    //     // Should revert when bond contract has insufficient rewards
    //     vm.expectRevert("Not enough rewards left");
    // }
}
