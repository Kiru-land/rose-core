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
 * @title Kiru Bond
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
contract Bond {

    //////////////////////////////////////////////////////////////
    /////////////////////////// STATE ////////////////////////////
    //////////////////////////////////////////////////////////////

    INonfungiblePositionManager constant positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint24 constant poolFee = 10000; // 1%
    bool positionCreated = false;
    uint256 positionId;

    // full range ticks
    int24 constant MIN_TICK = -887200;
    int24 constant MAX_TICK = 887200;

    address immutable kiru;
    address constant locker = 0xFD235968e65B0990584585763f837A5b5330e6DE;
    address constant treasury = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    //////////////////////////////////////////////////////////////
    //////////////////////// CONSTRUCTOR /////////////////////////
    //////////////////////////////////////////////////////////////

    constructor(address _kiru) {
        kiru = _kiru;
        IERC20(kiru).approve(address(positionManager), type(uint256).max);
        IERC20(WETH9).approve(address(positionManager), type(uint256).max);
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// BOND ////////////////////////////
    //////////////////////////////////////////////////////////////

    function bond(uint outMin, uint amount0Min, uint amount1Min) external payable {
        require(msg.value > 0, "No ETH sent");
        /*
         * Compute the amount of kiru received if msg.value was deposited
         */
        uint quoteKiru = IKiru(kiru).quoteDeposit(msg.value);
        /*
         * Compute the amount of Kiru reward to receive
         */
        uint reward = quoteKiru * 120000 / 100000;
        require(IERC20(kiru).balanceOf(address(this)) > reward, "Not enough rewards left");

        uint256 halfETH = msg.value / 2;
        /*
         * Deposit half ETH into Kiru's bonding curve, compute amount out
         */
        uint balanceBeforeSwap = IERC20(kiru).balanceOf(address(this));
        IKiru(kiru).deposit{value: halfETH}(outMin);
        uint balanceAfterSwap = IERC20(kiru).balanceOf(address(this));
        require(balanceAfterSwap > balanceBeforeSwap, "Swap failed");

        IWETH9(WETH9).deposit{value: address(this).balance}();

        uint256 amount0Desired = IERC20(WETH9).balanceOf(address(this));
        uint256 amount1Desired = balanceAfterSwap - balanceBeforeSwap;

        uint256 refund0;
        uint256 refund1;

        if (!positionCreated) {
            INonfungiblePositionManager.MintParams memory mintParams =
            INonfungiblePositionManager.MintParams({
                token0: WETH9,
                token1: kiru,
                fee: poolFee,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: block.timestamp
            });
            /*
             * Add liquidity
             */
            (uint256 tokenId, uint256 liquidity, uint256 amount0Refunded, uint256 amount1Refunded) = positionManager.mint(mintParams);
            positionId = tokenId;
            positionCreated = true;
            refund0 = amount0Refunded;
            refund1 = amount1Refunded;

            /*
             * Lock liquidity
             */
            uint256 unlockDate = block.timestamp + 365 days;
            uint16 countryCode = 66;
            IUNCX_LiquidityLocker_UniV3.LockParams memory lockParams = IUNCX_LiquidityLocker_UniV3.LockParams(
                positionManager,
                tokenId,
                treasury,
                treasury,
                address(0),
                treasury,
                unlockDate,
                countryCode,
                "DEFAULT",
                new bytes[](0)
            );
            positionManager.approve(address(locker), tokenId);
            IUNCX_LiquidityLocker_UniV3(locker).lock(lockParams);
        } else {
            /*
             * Increase liquidity
             */
            INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp
            });
            (, uint256 amount0Refunded, uint256 amount1Refunded) = positionManager.increaseLiquidity(increaseParams);
            refund0 = amount0Refunded;
            refund1 = amount1Refunded;
        }

        /*
         * Refund leftover ETH and tokens to the sender
         */

        // if (refund0 > 0) {
        //     IWETH9(WETH9).withdraw(refund0);
        //     payable(msg.sender).transfer(refund0);
        // }
        // if (refund1 > 0) {
        //     IERC20(kiru).transfer(msg.sender, refund1);
        // }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
