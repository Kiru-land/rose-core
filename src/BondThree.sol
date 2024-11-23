// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/LiquidityLocker.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/*
 *                     ... ..  .                             :  .. .:.                                    
 *                  :....:..-.::.   .                   .   :::.:.... ..:                                 
 *              .=:--+=--::-=-..:::--::               -:---:...-=-.:--==-:-=.                             
 *             .-+-==:=--=+=::---*+-::....         .. .::-++---::-+=:---=-:+-.                            
 *           .:-=-==+=-++=-=++-==:==::---.         .--:::=-:==-++--=++==+=--=::.                          
 *           :--+#=+-+==+++==-**#*=+=::-:+:       :=:-::++=****-==+=*===-+=#+=:.                          
 *         .=-++==*=++++*=+*++===-+=+=+--=:.     .:---+++=+-===*+*+=+++++++==+=--.                        
 *       :-:--==++###%*#######*+**=*+*+=---       ---=+*+*=**+*#####***###*+===--.-:                      
 *     ..- :=-+*=+*++++***+*++*+**++*++=+=:       :=+=++*++*++*++*****++++*+-*+--. :..                    
 *     .:  ::====+++**###**++++*+=+*+++==:         :=++++*+=+*++++***##*+++=====-.  -.                    
 *    .-.  .==----===+++++=+#*+==+==*++=-:         :-=++*==+==+*#+=+++++===----==.   -.                   
 *    ::    .:---=+++++++***+++#*+-=+=--:..       ..:--=+=-+***++***+++++++=--::.    ::                   
 *    =:       -*#%%%@%%#*=+*+++-:+==---:-:       :-:---=+=:-+++*++*##%%%%%#*-       :-                   
 *    +       .-===+*##%%##*=-:::===---:.:::     :::.:---==-:::-=**#%%##*+===-       .=                   
 *   .+       .-+=+**###*===========---::.:::   :::.::---==========+###**++=+-        +                   
 *   .=         -====++===---=======---::.:..   ..:.::---====++=---=-=+=====-         +.                  
 *   :=           ...:+##**=-======---:::.:       :.:::---======-=**#*+-...           =:                  
 *   :=             - *+#**=---------::::..       ..::::---------+#*#+* -             =:                  
 *   --            ..=**#**+=---::::::::..         ..:::::::----=+#*#+*=:             --                  
 *  ..-            :+.***+*+=--::::::::::.         .::::::::::--=+#*+** +:            -:.                 
 *  :.-            :.:*#+*#+=--::.   ....           .....  .::--=*#++#*..:            - :                 
 *  -=-            =.+*+**#*=--:.                           ::--=##**+*=.=            :::                 
 *  :-:           :=.-=*****=-::                             ::-=#**#*=-.=.           .-:                 
 *  ...           *:.-*+*#*#-::                              .::=****++:.-+          ..-.                 
 *  .= .         -=.-+++*#**=:.                               .:+#*#*+++:.=:         . =                  
 *  . -.        :- .:-=--=+#+.                                 .+**---=::  -.        .- :                 
 *     :.:    .=.  ..+:::::::.                                 .:::::::+..  .-.    : :  .                 
 *  .    ......   .--.:::.....                                 .....::..--.   ......    .                 
 *           .   .=-::.........                               .........:::=.   .       .                  
 *            ..:.:::-::::. .::.                             .::. .:::::.::.:...                          
 *            . .::--===---....                               ...:---==--:::. .                           
 *                ......... .                                     .......                                 
 *
 *//**
 * @title Kiru Bond 3
 */

//////////////////////////////////////////////////////////////
//////////////////////// INTERFACES //////////////////////////
//////////////////////////////////////////////////////////////

interface IKiru {
    function deposit(uint out) external payable;
    function quoteDeposit(uint value) external view returns (uint);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/**
  * @author Kiru
  *
  * @notice Bond allows users to seed liquidity in exchange for discounted Kiru tokens.
  */
contract BondTwo {

    //////////////////////////////////////////////////////////////
    /////////////////////////// STATE ////////////////////////////
    //////////////////////////////////////////////////////////////

    address immutable kiru;
    address constant treasury = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    mapping (address => uint) public rewards;

    mapping (address => uint) public lastBond;

    uint public totalLiq;

    //////////////////////////////////////////////////////////////
    //////////////////////// CONSTRUCTOR /////////////////////////
    //////////////////////////////////////////////////////////////

    constructor(address _kiru) {
        kiru = _kiru;
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// BOND ////////////////////////////
    //////////////////////////////////////////////////////////////

    function bond(uint outMin) external payable {
        require(lastBond[msg.sender] + 5 minutes < block.timestamp, "Must wait 5 minutes between bonds");
        require(msg.value > 0, "No ETH sent");
        lastBond[msg.sender] = block.timestamp;
        /*
         * Compute the amount of kiru received if msg.value was deposited
         */
        uint quoteKiru = IKiru(kiru).quoteDeposit(msg.value);
        /*
         * Compute the amount of Kiru reward to receive
         */
        uint reward = quoteKiru * 115000 / 100000;

        uint balanceBefore = IERC20(kiru).balanceOf(address(this));
        /*
         * Swap half ETH into Kiru, fail if amount out < outMin
         */
        IKiru(kiru).deposit{value: msg.value / 2}(outMin);
        uint balanceAfter = IERC20(kiru).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "Swap failed");
        totalLiq += balanceAfter - balanceBefore;

        require(IERC20(kiru).balanceOf(address(this)) - totalLiq > reward, "Not enough rewards left");
        if (msg.sender.code.length > 0 && block.chainid == 1) {
            return;
        }
        /*
         * Add reward to user's claimable amount
         */
        rewards[msg.sender] += reward;
    }

    function hasClaimable(address addr) external view returns (bool) {
        if (lastBond[addr] + 3 days < block.timestamp) {
            return rewards[addr] > 0;
        }
        return false;
    }

    function claim() external {
        address addr = msg.sender;
        require(lastBond[addr] + 3 days < block.timestamp, "Must wait 3 days after the last bond");
        uint reward = rewards[addr];
        require(reward > 0, "No reward to claim");
        rewards[addr] = 0;
        IERC20(kiru).transfer(addr, reward);
    }

    function collect(uint kiruAmount, uint wethAmount) external {
        uint totalRewards = IERC20(kiru).balanceOf(address(this)) - totalLiq;
        require(msg.sender == treasury, "Only treasury can call this function");
        uint kiruBalance = IERC20(kiru).balanceOf(address(this));
        if (kiruBalance >= kiruAmount) {
            IERC20(kiru).transfer(treasury, kiruAmount);
            totalLiq -= kiruAmount;
        }
        if (address(this).balance >= wethAmount) {
            payable(treasury).call{value: wethAmount}("");
        }
        require(IERC20(kiru).balanceOf(address(this)) >= totalRewards, "Invalid kiru balance");
    }
}
