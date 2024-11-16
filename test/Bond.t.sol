// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Bond} from "../src/Bond.sol";
import {Kiru} from "../src/Kiru.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3PoolState} from "../src/interfaces/IUniswapV3PoolState.sol";
import "../src/interfaces/LiquidityLocker.sol";

// Mock contracts for testing
contract BondTest is Test {
    Bond public bond;
    address payable kiru = payable(0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2);
    INonfungiblePositionManager constant positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    
    // Constants
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint24 constant POOL_FEE = 10000; // 1%
    int24 constant MIN_TICK = -887200;
    int24 constant MAX_TICK = 887200;
    address TREASURY = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;
    address constant locker = 0xFD235968e65B0990584585763f837A5b5330e6DE;
    address constant treasury = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    // Events to track
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        // Deploy Bond contract
        bond = new Bond(address(kiru));
        assertEq(IERC20(WETH9).allowance(address(bond), address(positionManager)), type(uint256).max);
        assertEq(IERC20(kiru).allowance(address(bond), address(positionManager)), type(uint256).max);
        // Transfer some Kiru tokens to Bond contract for rewards
        vm.deal(address(this), 100_000 * 1e18);
        
        // Label addresses for better trace output
        vm.label(address(kiru), "KIRU");
        vm.label(address(bond), "BOND");
        vm.label(WETH9, "WETH");
        vm.label(TREASURY, "TREASURY");
    }

    function testSuccessfulBond() public {
        // Setup
        _seedKiru();
        uint256 ethAmount = 0.001 ether;
        uint256 initialBondKiruBalance = IERC20(kiru).balanceOf(address(bond));
        
        // Execute bond
        bond.bond{value: ethAmount}(0, 0, 0);
        uint256 positionId = bond.positionId();
        
        // Assertions
        assertTrue(IERC20(kiru).balanceOf(address(bond)) < initialBondKiruBalance, "Bond contract should spend Kiru");
        assertTrue(positionManager.ownerOf(positionId) == address(locker), "Bond contract should be the owner of the position");
        assertTrue(address(bond).balance == 0, "Bond contract should have no ETH left");
    }

    function testBondWithZeroEth() public {
        _seedKiru();
        vm.expectRevert("No ETH sent");
        bond.bond(0, 0, 0);
    }

    // function testBondWithInsufficientRewards() public {
    //     // Drain the bond contract of its Kiru tokens
    //     // vm.prank(address(bond));
    //     // IERC20(kiru).transfer(address(1), IERC20(kiru).balanceOf(address(bond)));
        
    //     vm.expectRevert("Not enough rewards left");
    //     bond.bond{value: 1000000000 ether}(0, 0, 0);
    // }

    function testMultipleBonds() public {
        _seedKiru();
        // Test multiple users bonding
        address user1 = address(0x1);
        address user2 = address(0x2);
        
        // Fund users
        vm.deal(user1, 2 ether);
        vm.deal(user2, 2 ether);
        
        // First bond creates the position
        vm.prank(user1);
        bond.bond{value: 1 ether}(0, 0, 0);
        assertTrue(bond.positionCreated(), "Position should be created");
        assertTrue(bond.positionId() != 0, "Position ID should be set");
        (   
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 liquidity1,
            ,
            ,
            ,
            
        ) = positionManager.positions(bond.positionId());
        
        // Second bond increases liquidity
        vm.prank(user2);
        bond.bond{value: 1 ether}(0, 0, 0);

        (   
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 liquidity2,
            ,
            ,
            ,
            
        ) = positionManager.positions(bond.positionId());

        assertTrue(liquidity2 > liquidity1, "Liquidity should increase");
    }

    receive() external payable {} // Allow contract to receive ETH

    function _seedKiru() internal {
        vm.prank(TREASURY);
        Kiru(kiru).transfer(address(bond), 75000000000000000000000000000);
    }
}
