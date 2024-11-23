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
}

contract Deposit2 {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    address public constant KIRU = 0x0000000000000000000000000000000000000000;
    address public constant TREASURY = 0x0000000000000000000000000000000000000000;

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
      * 
      */
    function deposit(uint out) external payable {
        uint deltaIn = msg.value / beta;

        KIRU.call{value: deltaIn}("");
        IKiru(KIRU).deposit{value: msg.value - deltaIn}(out);

        uint deltaOut = out / beta;

        IKiru(KIRU).transfer(msg.sender, out - deltaOut);
        IKiru(KIRU).transfer(address(0), deltaOut);
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
        uint deltaIn = value / 1000;
        uint quote = _quoteDeposit(value - deltaIn, r0 + deltaIn, r1, alpha);
        uint deltaOut = quote / 1000;
        return quote - deltaOut;
    }

    function _quoteDeposit(uint value, uint r0, uint r1, uint alpha) internal view returns (uint) {
        assembly {
            let ptr := mload(0x40)
            let alphaR0 := div(mul(alpha, r0), 1000000)
            let alphaR1 := div(mul(alpha, r1), 1000000)
            let alphaR0Prime := add(alphaR0, value)
            let alphaR1Prime := div(mul(alphaR0, alphaR1), alphaR0Prime)
            let y := sub(alphaR1, alphaR1Prime)
            mstore(ptr, y)
            return(ptr, 0x20)
        }
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// Beta /////////////////////////////
    //////////////////////////////////////////////////////////////

    function setBeta(uint _beta) external {
        require(msg.sender == TREASURY, "!treasury");
        beta = _beta;
    }
}
