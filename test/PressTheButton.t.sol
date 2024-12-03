// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PressTheButton} from "../src/PressTheButton.sol";

// Mock contracts for testing
contract PressTheButtonTest is Test {

    PressTheButton public pressTheButton;
    address private constant MULTISIG = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    function setUp() public {
        pressTheButton = new PressTheButton();
        vm.startPrank(MULTISIG);
        pressTheButton.startWindow{value: 1 ether}();
    }

    function test_duration(uint256 speed, uint warp0, uint warp1) public {
        speed = bound(speed, 0.01 ether, 1 ether);
        pressTheButton.press{value: speed}();
        uint256 duration = pressTheButton.getDuration();
        emit log_uint(duration);
        warp0 = bound(warp0, 0, duration-1);
        vm.warp(block.timestamp + warp0);
        assertTrue(pressTheButton.checkDuration());
        warp1 = bound(warp1, duration, block.timestamp + 1e8);
        vm.warp(block.timestamp + warp1);
        assertFalse(pressTheButton.checkDuration());
    }
}
