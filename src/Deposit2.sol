// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

/*
 *                                         @@@@@@@@@@@@@@@@@                                  
 *                                         %%%%%%%%%%%%%%%%%                                  
 *                                                                                            
 *                                          -----  ::::::-                                    
 *                                         ===-.      :--=--                                  
 *                                      ==*==-=-.:=---.:--=+-                                 
 *                                      =#:*#+=+#%*-@-+#*%%:=-                                
 *                                     =##=*-#@##%@-%@#%*.%*-=-                               
 *                                    ====#%##*=-##*#@*:+:=--=--                              
 *                                    ==--.:=---=--*--##%#---+=-                              
 *                                   =-=-----=--+*%@@@@%%%*--*=--                             
 *                                  ===----*#++*%@@@@#+***+-.=+--                             
 *                                  =-=---+*+*#%%%%%%%%****--##--                             
 *                                  ==--.-:...:+##%%##=...::-=---                             
 *                                 ===--.-=+:=+#*#@##*+:==#:==@=-                             
 *                               ===-*+*.-*%%@@@%%##%@@@%%=-.++--                             
 *                             ====..*=-.:-+#%%%#*==+=%%#-- ==---                             
 *                           ===-- :==--:  .-*+#**##*+##--.+*****#######                      
 *                          ==--:%%%@@@@%%%@%-=*@@#*+=:-=#@@@@@@@@@@@%%*                      
 *                         ==----=+##%@@@@%%*#+%@%*+++==-**%@@@@%%#***                        
 *                        ==--*====-%%@@@@@%%*%#*+*#%%-==@*@%%@@@@%%%                         
 *                    ==== -==+==:-==+#%%%#%*%#*+###*-=-#@%#%#@@%%#:---                       
 *                ==   -===*=---.=-----#%#+%@#**@@====-#%%**+%###--. --====                   
 *              ==  --==+*++++++=--.  :.-*%@%*+@@---*##=%@*=+==----=-:----==                  
 *             ======-#%##%@@@@@@@@@##--+@%%*+***---++=-+@@#*--=- ---==-- ---                 
 *             =----=+@@@@*@@@@@@@@@@@@%+#**+%%###=-*=-=-%@%*++=====---==----                 
 *           =====---=%%%%%@@@%%%%@%%%%%%%#+#%@@%#+--=*%%*%@#+%@%%%@@%*=-=-==                 
 *        =*#=-------#%@@%%@%@@@@@@@@@@@@@%#%%%%*-=#+******%##+##%@@@@@%%*==                  
 *       =+---     ===+%@@*%=+**%%%%%###@@@@@@@%--=+*#%*#%%*@%#***#%%##%%=%#**                
 *      =---      -==--%%%%@@@#*##%%@@@@@@@@@@@%%*=+*%%#%%%+%@@#+%%*##@#*#%*@#                
 *      =-=------==-: +=-*@@@##*+=++*%%@@@@@@@%%##-+@@%#%#%%%*%@#*#%%*##*@%#%+=               
 *     ===**==---+@%+=====#%%@*+@@@%#@%#*#@@@@%%#**%+-%%#%##%%%*@#+%#%*+@%#%+===              
 *     -*+--..---.--===@==-#%%#%#%*%@%#%%@%#@%%###+%@@+@%###@#%%%*@##**+%*@*-+*=              
 *     ==. ---..**--=====--==+*%@##@@####%%%#%###%%%@@@@@###%###***%#***+%* --==              
 *     -.:-----=--=+==--.:--   *%%@%**%##%###%#@#%%%%%%%###%###*=*%#+#*+**+---=-              
 *     --    ---=**--. :---    ==*#@@+%@@%##%%*@#%*@@%#=+@####*#*#*##%#*    --=               
 *      = --===-::. :-----    =*#%%%*+%%%%%**%#*##*%#*%#*%%#%%*####@@#*     --=               
 *       -=----=-.---- =--   ++#%@%**=*%%%#**####@@%*  *#***%@@%**##*                         
 *       ==+- =*==---  -.-   =*%@%#*+=%@%%*+                ***                               
 *       ==- =---==- -=-:-   +#@@%*+=#%@@%*+                                                  
 *        =----=+--  -=--    +%@%*+ =#%@@%*+                                                  
 *         =   ==    -===    +@@#*= *%@@%#*=                                                  
 *          =====    -=---  =#@%*=  *%@%%*=                                                   
 *                    ==--- =%@#*= =%@@%*+                                                    
 *                      =---=%%*+  =%@@#*=                                                    
 *                        ==#%#*= =%@@#+=                                                     
 *                         *%%#*= *@@#*=                                                      
 *                        =%%%*= +%@%*=-                                                      
 *                       =%%@%*==%%@#+=                                                       
 *                       *#%@%*+#@@%*+                                                        
 *                      **#%**+%%%#***                                                        
 *                     **%%##**#@@@#**                                                        
 *                      **%#%==#%*%#*=                                                        
 *                        *@%##%@%##**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              
 *
 *//**
 * @title Deposit v2 👼🏻
 *
 * @author Kiru
 *
 * @notice Deposit v2
 *         increased burn rate, better price action
 */

//////////////////////////////////////////////////////////////
//////////////////////// Interfaces //////////////////////////
//////////////////////////////////////////////////////////////

interface IKiru {
    function deposit(uint) external payable;
    function transfer(address, uint) external;
    function getState() external view returns (uint, uint, uint);
    function balanceOf(address) external view returns (uint);
}

contract Deposit2 {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    address public constant KIRU = 0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2;
    address public constant TREASURY = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    uint beta;

    //////////////////////////////////////////////////////////////
    //////////////////////// Constructor /////////////////////////
    //////////////////////////////////////////////////////////////

    constructor(uint _beta) {
        beta = _beta;
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// Buy /////////////////////////////
    //////////////////////////////////////////////////////////////


    /**
      * @notice Deposit ETH into the pool and receive KIRU
      *
      * @dev Aggressive skewness and burn rate
      *      Part of the deposit is collected to be reinjected into
      *      the pool to increase the reserves ratio.
      *      Part of the amount received is burned to decrease the
      *      circulating supply.
      *
      * @param outMin The minimum amount of KIRU received from the
      *               Kiru contract.
      */
    function deposit(uint outMin) external payable {
        /*
         * compute Δin, the value to inject into the pool
         */
        uint deltaIn = msg.value / beta;
        /*
         * inject Δin into the pool before the deposit
         */
        (bool success,) = KIRU.call{value: deltaIn}("");
        require(success, "!success");

        uint kiruBalanceBefore = IKiru(KIRU).balanceOf(address(this));
        /*
         * deposit the remaining ETH into the pool
         */
        IKiru(KIRU).deposit{value: msg.value - deltaIn}(outMin);
        /*
         * retrieve the KIRU amount received
         */
        uint out = IKiru(KIRU).balanceOf(address(this)) - kiruBalanceBefore;
        /*
         * compute the KIRU amount to burn
         */
        uint deltaOut = out / beta;
        /*
         * burn KIRU
         */
        IKiru(KIRU).transfer(address(0), deltaOut);
        /*
         * send KIRU to the caller
         */
        IKiru(KIRU).transfer(msg.sender, out - deltaOut);
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Quote /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Computes the amount of KIRU received for a given amount of ETH deposited
      *         given the current market reserves.
      *
      * @param value The amount of ETH to deposit.
      *
      * @return The amount of KIRU received.
      */
    function quoteDeposit(uint value) public view returns (uint) {
        (uint r0, uint r1, uint alpha) = IKiru(KIRU).getState();
        uint deltaIn = value / beta;
        uint quote = _quoteDeposit(value - deltaIn, r0 + deltaIn, r1, alpha);
        uint deltaOut = quote / beta;
        return quote - deltaOut;
    }

    function _quoteDeposit(uint value, uint r0, uint r1, uint alpha) internal view returns (uint) {
        uint alphaR0 = alpha * r0 / 1000000;
        uint alphaR1 = alpha * r1 / 1000000;
        uint alphaR0Prime = alphaR0 + value;
        uint alphaR1Prime = alphaR0 * alphaR1 / alphaR0Prime;
        uint y = alphaR1 - alphaR1Prime;
        return y;
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// Beta /////////////////////////////
    //////////////////////////////////////////////////////////////

    function setBeta(uint _beta) external {
        require(msg.sender == TREASURY, "!treasury");
        beta = _beta;
    }
}
