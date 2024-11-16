// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IWETH9 {
    function deposit() external payable;
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

    // full range ticks
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;

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
    event log(string, uint);
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
        // require(IERC20(WETH9).approve(address(positionManager), amount0Desired), "WETH9 approval failed");
        // require(IERC20(kiru).approve(address(positionManager), amount1Desired), "Kiru approval failed");

        emit log("amount0Desired", amount0Desired);
        emit log("amount1Desired", amount1Desired);
        emit log("weth balance", IERC20(WETH9).balanceOf(address(this)));
        emit log("kiru balance", IERC20(kiru).balanceOf(address(this)));

        INonfungiblePositionManager.MintParams memory params =
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
                deadline: block.timestamp + 100000
            });

        /*
         * Add liquidity, then send remaining ETH to the position manager
         */
        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = positionManager.mint(params);

        // /*
        //  * Refund leftover ETH and tokens to the sender
        //  */
        // uint256 refundETH = (msg.value - halfETH) - amount0;
        // uint256 refundToken = amountTokenOut - amount1;

        // if (refundETH > 0) {
        //     payable(msg.sender).transfer(refundETH);
        // }

        // if (refundToken > 0) {
        //     IERC20(kiru).transfer(msg.sender, refundToken);
        // }

        // /*
        //  * Send the reward to the sender
        //  */
        // IERC20(kiru).transfer(msg.sender, reward);
    }
}
