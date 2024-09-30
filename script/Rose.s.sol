// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

import { Script } from "forge-std/Script.sol";
import { Rose } from "../src/Rose.sol";

contract RoseScript is Script {

    Rose public rose;

    // TODO: change to actual parameters
    uint256 public constant R0_INIT = 1e17;
    uint256 public constant ALPHA = 1e5;
    uint256 public constant PHI = 1e4;
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant R1_INIT = 200_000_000 * 1e18;
    uint256 public constant FOR_SALE = 620_000_000 * 1e18;
    uint256 public constant TREASURY_ALLOCATION = 80_000_000 * 1e18;
    uint256 public constant CLAWBACK = 100_000_000 * 1e18;
    address public constant TREASURY = address(0x3);

    function run() external {
        vm.startBroadcast();
        rose = new Rose{salt: "REDROSE", value: R0_INIT}(
            ALPHA, 
            PHI, 
            R1_INIT, 
            SUPPLY,
            TREASURY
        );
        vm.stopBroadcast();
    }
}
