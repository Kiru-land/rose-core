// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

/*
  * Welcome to Kiru Land.
  *
  *//**
  * @title Kiru 👼🏻
  *
  * @author Kiru
  *
  * @notice Kiru is an efficient contract for the Kiru tokenized bonding curve.
  *         Unification of the asset and it's canonical market under a single
  *         contract allows for precise control over the market-making strategy,
  *         fully automated.
  *
  *            ::::                                       °      ::::
  *         :::        .           ------------             .        :::
  *        ::               °     |...       ° | - - - - ◓             ::
  *        :             o        |   ...  .   |                        :
  *        ::          .          |  °   ...   |                       ::
  *         :::         ◓ - - - - |   .     ...|                     :::
  *            ::::                ------------                  ::::
  *
  * @dev Jita market, the bonding-curve of the Kiru token, executes buys and
  *      sells with different dynamics to optimise for price volatility on buys
  *      and deep liquidity on sells.
  *      Driven by the skew factor α(t), Jita binds price appreciation to
  *      uniform volume.
  */
contract Kiru {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    /*
     *                                                      -===:                                        
     *                                            :-*%%%#**#@@@@@@%#-.                                   
     *                                        .+#@@@@@@@@@@@%#%@@@@@@@%*:                                
     *                                       +%@@@@@@@@@@@%%@@%#%@@@@@@%%%#:                             
     *                                     +%@@@@@@@@@%%%@@@@@%###@@%##%%@@@#                            
     *                                   =#@@@%%%@@@@@@@@@@@@%####%###**%@@@@@*                          
     *                                  -%@@@%@@@@@@@@@@@@@%##*##*##****%@@@@@@@+                        
     *                                 -#@%%@@@%@@@@@@@@@%######**#**###%%@@@@@@@+                       
     *                                .#@%%@%##@@@@@@@@%#**#%%%#****##**#%@@@@@@@@=                      
     *                                +%%#%%#%@@@@@@@%%#***#@@@@%#*###**#%@@@@@@@@@-                     
     *                               .*#*##%@@@@@@@%##**#%%@@@@@@@%@@@%#*#%%@@@@%%@@-                    
     *                               .+***%@@@@@@@%#*+=.   :#@@@@@@+. .=+*#%@@@@@#%@@-                   
     *                     =#%#*:    *#*#%@@@@@@%#**+:  :*%%%@@@@@%.=*=-:+#%%%@@@%*#%=                   
     *                  =@@@@@@@@@%**####@@@@@%#*+*+    :=+@@@@@@@%  :%# -*#%%@@@%==#-                   
     *                -%@@@@@@@@@@@@##%##@@@@%#****.  .   -@@@@@@@@. .@@*=+#%%%@@%--=                    
     *              :%@@@@@@@@@@%@%#%%%##%@@@%*+*##-#*-..:*@@@@@@@@=:+@@%++*#%%@@%::.                    
     *             +@@@@@@@@@@%=:=#%%###*#%@%#*==*##%-.  .+@@@@@@%%:-#@%=+#*#%%@@-                       
     *            +@@@@@@@@@@@=  :*##**#***##***+=+*#*+==*@@@@%%%@@@@@#+=*###%%@*                        
     *           +@@@@@@@@@@@+   :*#*+*#*****##***+==*#%@@@@@#+*@@@%*+=+*%%##%%@#.                       
     *          =@@@@@@@@@@@#.   :**-.+#*****#**##+=---==+#%%%%%#*===++*#%####%@@@:                      
     *         =@@@@@@@@@@@@*     =*:  **=-+*+*+++*##++**+==+*+=-=+*#**###=+*##%@@%:                     
     *        -@@@@@@@@@@@@#       -.   -:      :*@@@@#++*%@@@%##+=++=*#%+ -*#+*@@@=                     
     *       :%@@@@@@@@@@@@#                    :+%@@@@%#++%@@*+##+-..+%*  -*#..*@@@:                    
     *      :%@@@@@@@@@@@@@#                     -+#%@@@@%*++#*+#%%+:.:*=  -#*+ :%@@:                    
     *     :%@@@@@@@@@@@@@@#                    .=##++#@@@@%*+=+%@@%+:     -*+  :%@#.                    
     *    .%@@%%@@@%@@@@@@@#                    =#%%%*++%@@@@%*+*%@@%=.    ::   :%#:                     
     *    .%@-.=@@@%@@@@@@@%:                  -*%%@@@%*+*%@@@@%+=%@@%=         :#+                      
     *    .+.   *@@##@@@%@@@*                 :+#%@@@@@@%*+*%@@@%++%@@%=        :+:                      
     *          .#@*:*@@%@@@*.                -*%@@@@@#*#%#*=+##*#++#%%#**+----                          
     *           .*+.=@@%+%@*.                -*%@@@@@*=*@@*=+---=*+%@@@%#%@@@@@#.                       
     *                =%*.-%%=            .-++=+#@@@@@%++%@%+=.   -#@@@@*%@@##@@@*.                      
     *                 .:  .**           -*%%#+=#@@@@@@#+#@@@*.   @@@@#*@@%*##+@@@%:                     
     *                                   =##=---+%@@@@@@*#@@@*.   @@@@#*@@%*##+@@@@-                     
     *                                   =**--**+#@@@@@%+*@@@*.   @@@@#*@@%*##+@@@@-                     
     *                                   =##+-*##*#@@@%*=*%%*:    @@@@**@@%*%%+@@@@-                     
     *                                   .====-*#%%%%#+=*##+:     .=****#@@%%%%@@%=                      
     *                                          :=+*+:.....        .=*###%@@@@@@@=                       
     *                                                               .+#*+*%%%%:                         
     *                                                                                                   
     *//**
     * @notice The Magical Token.
     */
    string public constant name = "Kiru";
    string public constant symbol = "KIRU";
    uint8 public constant decimals = 18;

    mapping(address => uint) private _balanceOf; // slot 0

    mapping(address => mapping(address => uint)) private _allowance; // slot 1

    uint cumulatedFees; // slot 2

    uint256 _totalSupply; // slot 3

    /**
      * @notice The initial skew factor α(0) scaled by 1e6
      */
    uint immutable ALPHA_INIT;
    /**
      * @notice The slash factor ϕ scaled by 1e6
      */
    uint immutable PHI_FACTOR;
    /**
      * @notice The initial reserve of KIRU R₁(0)
      */
    uint immutable R1_INIT;
    /**
      * @notice Buyback address
      */
    address public immutable TREASURY;

    /**
      * @notice constant storage slots
      */
    bytes32 immutable SELF_BALANCE_SLOT;
    bytes32 immutable TREASURY_BALANCE_SLOT;
    bytes32 immutable BURN_BALANCE_SLOT;

    /**
      * @notice event signatures
      */
    bytes32 constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 constant APPROVAL_EVENT_SIG = keccak256("Approval(address,address,uint256)");
    bytes32 constant BUY_EVENT_SIG = keccak256("Buy(address,uint256,uint256,uint256,uint256)");
    bytes32 constant SELL_EVENT_SIG = keccak256("Sell(address,uint256,uint256,uint256,uint256)");


    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event Buy(address indexed chad, uint amountIn, uint amountOut, uint r0, uint r1);
    event Sell(address indexed jeet, uint amountIn, uint amountOut, uint r0, uint r1);

    //////////////////////////////////////////////////////////////
    //////////////////////// Constructor /////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice t=0 state
      */
    constructor(
      uint _alpha,
      uint _phi, 
      uint _r1Init, 
      uint _supply,
      address _treasury
      ) payable {
        ALPHA_INIT = _alpha;
        PHI_FACTOR =  _phi;
        R1_INIT = _r1Init / 2;
        TREASURY = _treasury;
        _totalSupply = _supply;

        bytes32 _SELF_BALANCE_SLOT;
        bytes32 _TREASURY_BALANCE_SLOT;

        assembly {
            let ptr := mload(0x40)
            /*
             * Load balanceOf[address(this)] slot
             */
            mstore(ptr, address())
            mstore(add(ptr, 0x20), 0)
            _SELF_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Load balanceOf[_treasury] slot
             */
            mstore(ptr, _treasury)
            _TREASURY_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Set the initial balances
             */
            sstore(_SELF_BALANCE_SLOT, _r1Init)
            sstore(_TREASURY_BALANCE_SLOT, sub(_supply, _r1Init))
        }
        /*
         * set constants
         */
        SELF_BALANCE_SLOT = _SELF_BALANCE_SLOT;
        TREASURY_BALANCE_SLOT = _TREASURY_BALANCE_SLOT;
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// Buy /////////////////////////////
    //////////////////////////////////////////////////////////////


    /**
      * Nomenclature:
      *
      *      R₀ = ETH reserves
      *      R₁ = Kiru reserves
      *      x  = input amount
      *      y  = output amount
      *      K  = invariant R₀ * R₁
      *      α  = skew factor
      *      var(0) = value of var at t=0
      *      var(t) = value of var at time t
      *  
      *                               :::::::::::    
      *                           ::::     :     ::::
      *                        :::         :        :::
      *                       ::     R₀    :    R₁    ::
      *                       :............:...........:
      *      x - - - - - - -> ::       .   :          :: - - - - - - -> y
      *                        :::  °      :    °   :::
      *                           ::::     :  . :::::
      *                               :::::::::::                              
      *
      * @notice Deposit is the entry point for entering the Kiru bonding-curve
      *         upon receiving ETH, the kiru contract computes the amount out `y`
      *         using the [skew trading function](https://github.com/RedKiruMoney/Kiru).
      *         The result is an asymmetric bonding curve that can optimise for price
      *         appreciation, biased by the skew factor α(t).
      *
      *         The skew factor α(t) is a continuous function that dictates the
      *         evolution of the market's reserves asymmetry through time, decreasing
      *         as the ratio R₁(t) / R₁(0) decreases.
      *
      *             ^
      *             | :
      *             | ::
      *             | :::
      *             |  ::::
      *             |    :::::
      *             |        ::::::
      *             |              :::::::::
      *             |                       :::::::::::::
      *             ∘------------------------------------->
      *
      * @dev The skew factor α(t) is a continuous function of the markets reserves
      *      computed as α(t) = 1 − α(0) ⋅ (R₁(0) / R₁(t))
      *      The market simulates a lp burn of α(t) right before a buy.
      *      The skew factor α(t) represents the fraction of the current reserves that
      *      the LP is withdrawing.
      *      We have the trading function (x, R₀, R₁) -> y :
      *      
      *         αK = αR₀ * αR₁
      *         αR₁′ = αK / (αR₀ + x)
      *         y    = αR₁ - αR₁′
      *
      *      After computing the swapped amount `y` on cut reserves, the LP provides the
      *      maximum possible liquidity from the withdrawn amount at the new market rate:
      *
      *         spot = R₁ / R₀
      *         R₀′ = R₀ + x
      *         R₁′ = (R₀ * R₁) / R₀′
      *
      * @param out The minimum amount of KIRU to receive.
      *            This parameter introduces slippage bounds for the trade.
      */
    function deposit(uint out) external payable {
        uint _ALPHA_INIT = ALPHA_INIT;
        uint _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        bytes32 _BURN_BALANCE_SLOT = BURN_BALANCE_SLOT;
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        bytes32 _BUY_EVENT_SIG = BUY_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            let chad := caller()
            /*
             * Load balanceOf[msg.sender] slot
             */
            mstore(ptr, chad)
            mstore(add(ptr, 0x20), 0)
            let CALLER_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * x  = msg.value
             * R₀ = token₀ reserves
             * R₁ = token₁ reserves
             */
            let x := callvalue()
            let r0 := sub(sub(selfbalance(), sload(2)), callvalue())
            let r1 := sload(_SELF_BALANCE_SLOT)
            /*
             * Compute the skew factor α(t) if activated
             */
            let r1InitR1Ratio := mul(div(mul(r1, 1000000), _R1_INIT), gt(_R1_INIT, r1))
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            let alpha := sub(1000000, inverseAlpha)
            /*
             * α-reserves: reserves cut by the skew factor α(t)
             */
            let alphaR0 := div(mul(alpha, r0), 1000000)
            let alphaR1 := div(mul(alpha, r1), 1000000)
            /*
             * The new α-reserve 0, increased by x
             *
             * αR₀′ = αR₀ + x
             */
            let alphaR0Prime := add(alphaR0, x)
            /*
             * The new α-reserve 1, computed as the constant product of the α-reserves
             *
             * αR₁′ = (αR₀ * αR₁) / αR₀′
             */
            let alphaR1Prime := div(mul(alphaR0, alphaR1), alphaR0Prime)
            /*
             * The amount out y, computed as the difference between the initial α-reserve 1 and the new α-reserve 1
             *
             * y = αR₁ - αR₁′
             */
            let y := sub(alphaR1, alphaR1Prime)
            /*
             * The new actual reserve 0, increased by x
             *
             * R₀′ = R₀ + x
             */
            let r0Prime := add(r0, x)
            /*
             * The new actual reserve 1, computed as new reserve 0 * α-ratio
             * where α-ratio: αR₁′ / αR₀′
             *
             * R₁′ = (αR₁′ / αR₀′) * R₀′ + ϵ
             */
            let r1Prime := add(div(mul(div(mul(alphaR1Prime, 1000000), alphaR0Prime), r0Prime), 1000000), 1)
            /*
             * Delta between constant product of actual reserves and new reserve 1
             *
             * ΔR₁ = R₁ - R₁′ - y
             */
            let deltaToken1 := sub(sub(r1, r1Prime), y)
            /*
             * Ensures that the amount out is within slippage bounds
             */
            if gt(out, y) {revert(0, 0)}
            /*
             * Update the market reserves to (R₀′, R₁′) then update balances
             */
            sstore(_SELF_BALANCE_SLOT, r1Prime)
            let balanceOfCaller := sload(CALLER_BALANCE_SLOT)
            sstore(CALLER_BALANCE_SLOT, add(balanceOfCaller, y))
            let balanceOfBurn := sload(_BURN_BALANCE_SLOT)
            sstore(_BURN_BALANCE_SLOT, add(balanceOfBurn, deltaToken1))
            /*
             * decrease total supply
             */
            sstore(3, sub(sload(3), deltaToken1))
            /*
             * emit Transfer event
             */
            mstore(add(ptr, 0x20), y)
            log3(add(ptr, 0x20), 0x20, _TRANSFER_EVENT_SIG, address(), chad)
            /*
             * emit Buy event
             */
            mstore(ptr, x)
            mstore(add(ptr, 0x20), y)
            mstore(add(ptr, 0x40), r0Prime)
            mstore(add(ptr, 0x60), r1Prime)
            log2(ptr, 0x80, _BUY_EVENT_SIG, chad)
        }
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// Sell /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      *
      *            _____
      *          .'/L|__`.
      *         / =[_]O|` \
      *        |   _  |   |
      *        ;  (_)  ;  |
      *         '.___.' \  \
      *          |     | \  `-.
      *         |    _|  `\    \
      *          _./' \._   `-._\
      *        .'/     `.`.   '_.-.   
      *
      * @notice Withdraws ETH from Jita's bonding curve
      *
      * @dev This contracts operate at low-level and does not require sending funds 
      *      before withdrawing, it instead requires the caller to have enough
      *      balance, then balance slots gets updated accordingly.
      *
      * @param value The amount of KIRU to sell.
      *
      * @param out The minimum amount of ETH to receive.
      *            This parameter introduces slippage bounds for the trade.
      */
    function withdraw(uint value, uint out) external {
        uint _PHI_FACTOR = PHI_FACTOR;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        bytes32 _SELL_EVENT_SIG = SELL_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            /*
             * Load balanceOf[msg.sender] slot
             */
            let jeet := caller()
            mstore(ptr, jeet)
            mstore(add(ptr, 0x20), 0)
            let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * check that caller has enough funds
             */
            let balanceFrom := sload(FROM_BALANCE_SLOT)
            if lt(balanceFrom, value) { revert(0, 0) }
            let _cumulatedFees := sload(2)
            /*
             *  load market's reserves (R₀, R₁)
             *
             *      r₀ = ETH balance - cumulated fees
             *      r₁ = KIRU balance
             */
            let r0 := sub(selfbalance(), _cumulatedFees)
            let r1 := sload(_SELF_BALANCE_SLOT)
            let y := value
            /*
             * Only allow sell orders under 5% of Kiru's liquidity
             * to prevent divergence.
             */
            if gt(y, div(r1, 5)) { revert(0, 0) }
            /*
             * the kiru sent is sold for ETH using the CP formula:
             *
             *     y = (R₁ - K / (R₀ + x)) * ϕfactor
             *
             * where:
             *
             *    y: Kiru amount in
             *    x: Eth amount out
             *    K: R₀ * R₁
             *    ϕfactor: withdrawal penalty factor
             *
             * Compute the new reserve 1 by adding the amount out y
             * 
             * R₁′ = R₁ + y
             */
            let r1Prime := add(r1, y)
            /*
             * R₀′ = K / R₁′
             */
            let r0Prime := div(mul(r0, r1), r1Prime)
            /*
             * Compute the raw amount out x
             *
             * x = R₀ - R₀′
             */
            let raw_x := sub(r0, r0Prime)
            /*
             * Compute the withdrawal fee ϕ
             *
             * ϕ = x * ϕfactor
             */
            let phi := div(mul(raw_x, _PHI_FACTOR), 1000000)
            /*
             * Compute the amount out x
             *
             * x = x - ϕ
             */
            let x := sub(raw_x, phi)
            /*
             * Ensures that the amount out is within slippage bounds
             */
            if gt(out, x) {revert(0, 0)}
            /*
             * increment cumulated fees
             */
            sstore(2, add(_cumulatedFees, phi))
            /*
             * decrease sender's balance
             */
            sstore(FROM_BALANCE_SLOT, sub(balanceFrom, value))
            /*
             * increase bonding curve balance
             */
            sstore(_SELF_BALANCE_SLOT, add(sload(_SELF_BALANCE_SLOT), value))
            /*
             * Transfer ETH to the seller's address
             */
            if iszero(call(gas(), jeet, x, 0, 0, 0, 0)) { revert(0, 0) }
            /*
             * emit Transfer event
             */
            mstore(ptr, value)
            log3(ptr, 0x20, _TRANSFER_EVENT_SIG, jeet, address())
            /*
             * emit Sell event
             */
            mstore(ptr, value)
            mstore(add(ptr, 0x20), x)
            mstore(add(ptr, 0x40), r0Prime)
            mstore(add(ptr, 0x60), r1Prime)
            log2(ptr, 0x80, _SELL_EVENT_SIG, jeet)
        }
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
        uint _ALPHA_INIT = ALPHA_INIT;
        uint _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            let r0 := sub(selfbalance(), sload(2))
            let r1 := sload(_SELF_BALANCE_SLOT)
            let r1InitR1Ratio := mul(div(mul(r1, 1000000), _R1_INIT), gt(_R1_INIT, r1))
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            let alpha := sub(1000000, inverseAlpha)
            let alphaR0 := div(mul(alpha, r0), 1000000)
            let alphaR1 := div(mul(alpha, r1), 1000000)
            let alphaR0Prime := add(alphaR0, value)
            let alphaR1Prime := div(mul(alphaR0, alphaR1), alphaR0Prime)
            let y := sub(alphaR1, alphaR1Prime)
            mstore(ptr, y)
            return(ptr, 0x20)
        }
    }

    /**
      * @notice Computes the amount of ETH received for a given amount of KIRU withdrawn
      *         given the current market reserves.
      *
      * @param value The amount of KIRU to withdraw.
      *
      * @return The amount of ETH received.
      */
    function quoteWithdraw(uint value) public view returns (uint) {
        uint _PHI_FACTOR = PHI_FACTOR;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            let r0 := sub(selfbalance(), sload(2))
            let r1 := sload(_SELF_BALANCE_SLOT)
            let r1Prime := add(r1, value)
            let x := sub(r0, div(mul(r0, r1), r1Prime))
            let phi := div(mul(x, _PHI_FACTOR), 1000000)
            let xOut := sub(x, phi)
            mstore(ptr, xOut)
            return(ptr, 0x20)
        }
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// View /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Returns the market's reserves and the skew factor α(t).
      *
      * @return r0 The balance of the KIRU contract.
      *
      * @return r1 The balance of the KIRU contract.
      *
      * @return alpha The skew factor α(t).
      */
    function getState() public view returns (uint r0, uint r1, uint alpha) {
        uint _ALPHA_INIT = ALPHA_INIT;
        uint _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            r0 := sub(selfbalance(), sload(2))
            r1 := sload(_SELF_BALANCE_SLOT)
            let r1InitR1Ratio := mul(div(mul(r1, 1000000), _R1_INIT), gt(_R1_INIT, r1))
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            alpha := sub(1000000, inverseAlpha)
        }
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// KIRU ////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Returns the balance of the specified address.
      *
      * @param to The address to get the balance of.
      *
      * @return _balance The balance of the specified address.
      */
     function balanceOf(address to) public view returns (uint _balance) {
        assembly {
            let ptr := mload(0x40)
            /*
             * Load balanceOf[to] slot
             */
            mstore(ptr, to)
            mstore(add(ptr, 0x20), 0)
            let TO_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Load balanceOf[to]
             */
            _balance := sload(TO_BALANCE_SLOT)
        }
     }

    /**
      * @notice Returns the amount of tokens that the spender is allowed to transfer from the owner.
      *
      * @param owner The address of the owner.
      *
      * @param spender The address of the spender.
      *
      * @return __allowance The amount of tokens that the spender is allowed to transfer from the owner.
      */
     function allowance(address owner, address spender) public view returns (uint __allowance) {
        assembly {
            let ptr := mload(0x40)
            /*
             * Load allowance[owner][spender] slot
             */
            mstore(ptr, owner)
            mstore(add(ptr, 0x20), 1)
            let OWNER_ALLOWANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, spender)
            mstore(add(ptr, 0x20), OWNER_ALLOWANCE_SLOT)
            let SPENDER_ALLOWANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Load allowance[owner][spender]
             */
            __allowance := sload(SPENDER_ALLOWANCE_SLOT)
        }
     }

    /**
      * @notice Efficient ERC20 transfer function
      *
      * @dev The caller must have sufficient balance to transfer the specified amount.
      *
      * @param to The address to transfer to.
      *
      * @param value The amount of kiru to transfer.
      *
      * @return true
      */
    function transfer(address to, uint value) public returns (bool) {
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            /*
             * Load balanceOf[msg.sender] slot
             */
            let from := caller()
            mstore(ptr, from)
            mstore(add(ptr, 0x20), 0)
            let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Load balanceOf[to] slot
             */
            mstore(ptr, to)
            let TO_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Ensures that caller has enough balance
             */
            let balanceFrom := sload(FROM_BALANCE_SLOT)
            if lt(balanceFrom, value) { revert(0, 0) }
            /*
             * decrease sender's balance
             */
            sstore(FROM_BALANCE_SLOT, sub(balanceFrom, value))
            /*
             * increment recipient's balance
             */
            sstore(TO_BALANCE_SLOT, add(sload(TO_BALANCE_SLOT), value))
            /*
             * emit Transfer event
             */
            mstore(ptr, value)
            log3(ptr, 0x20, _TRANSFER_EVENT_SIG, from, to)
            /*
             * return true
             */
            mstore(ptr, 1)
            return(ptr, 0x20)
        }
    }

    /**
      * @notice Efficient ERC20 transferFrom function
      *
      * @dev The caller must have sufficient allowance to transfer the specified amount.
      *      From must have sufficient balance to transfer the specified amount.
      *
      * @param from The address to transfer from.
      *
      * @param to The address to transfer to.
      *
      * @param value The amount of kiru to transfer.
      *
      * @return true
      */
    function transferFrom(address from, address to, uint value) public returns (bool) {
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            /*
             * Load balanceOf[from] slot
             */
            let spender := caller()
            mstore(ptr, from)
            mstore(add(ptr, 0x20), 0)
            let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Load balanceOf[to] slot
             */
            mstore(ptr, to)
            let TO_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * Load allowance[from][spender] slot
             */
            mstore(ptr, from)
            mstore(add(ptr, 0x20), 1)
            let ALLOWANCE_FROM_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, spender)
            mstore(add(ptr, 0x20), ALLOWANCE_FROM_SLOT)
            let ALLOWANCE_FROM_CALLER_SLOT := keccak256(ptr, 0x40)
            /*
             * check that msg.sender has sufficient allowance
             */
            let __allowance := sload(ALLOWANCE_FROM_CALLER_SLOT)
            if lt(__allowance, value) { revert(0, 0) }
            /*
             * Reduce the spender's allowance
             */
            sstore(ALLOWANCE_FROM_CALLER_SLOT, sub(__allowance, value))
            /*
             * Ensures that from has enough funds
             */
            let balanceFrom := sload(FROM_BALANCE_SLOT)
            if lt(balanceFrom, value) { revert(0, 0) }
            /*
             * Decrease sender's balance
             */
            sstore(FROM_BALANCE_SLOT, sub(balanceFrom, value))
            /*
             * Increment recipient's balance
             */
            sstore(TO_BALANCE_SLOT, add(sload(TO_BALANCE_SLOT), value))
            /*
             * Emit Transfer event
             */
            mstore(ptr, value)
            log3(ptr, 0x20, _TRANSFER_EVENT_SIG, from, to)
            /*
             * Return true
             */
            mstore(ptr, 1)
            return(ptr, 0x20)
        }
    }

    
    /**
      * @notice Approves a spender to transfer KIRU tokens on behalf of the caller
      *         This function implements the ERC20 approve functionality, allowing
      *         delegation of token transfers to other addresses.
      *
      * @dev This function sets the allowance that the spender can transfer from
      *      the caller's balance. The allowance can be increased or decreased
      *      by calling this function again with a different value.
      *      Note that setting a non-zero allowance from a non-zero value should
      *      typically be done by first setting it to zero to prevent front-running.
      *
      * @param to The address being approved to spend tokens
      *
      * @param value The amount of tokens the spender is approved to transfer
      *
      * @return bool Returns true if the approval was successful
      */
    function approve(address to, uint value) public returns (bool) {
        bytes32 _APPROVAL_EVENT_SIG = APPROVAL_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            /*
             * Load allowance[owner][spender] slot
             */
            let owner := caller()
            mstore(ptr, owner)
            mstore(add(ptr, 0x20), 1)
            let ALLOWANCE_CALLER_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, to)
            mstore(add(ptr, 0x20), ALLOWANCE_CALLER_SLOT)
            let ALLOWANCE_CALLER_TO_SLOT := keccak256(ptr, 0x40)
            /*
             * Store the new allowance value
             */
            sstore(ALLOWANCE_CALLER_TO_SLOT, value)
            /*
             * Emit Approval event
             */
            mstore(ptr, value)
            log3(ptr, 0x20, _APPROVAL_EVENT_SIG, owner, to)
            /*
             * Return true
             */
            mstore(ptr, 1)
            return(ptr, 0x20)
        }
    }

    /**
      * @notice Burns KIRU tokens from the caller's balance
      *         The burned tokens are permanently removed from circulation,
      *         reducing the total supply.
      *
      * @dev This function requires the caller to have sufficient balance.
      *      The tokens are burned by transferring them to the zero address
      *      and decreasing the total supply.
      *
      * @param value The amount of KIRU tokens to burn
      */
    function burn(uint value) public {
      bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
      assembly {
        let ptr := mload(0x40)
        let from := caller()
        mstore(ptr, from)
        mstore(add(ptr, 0x20), 0)
        let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
        let balanceFrom := sload(FROM_BALANCE_SLOT)
        if lt(balanceFrom, value) { revert(0, 0) }
        sstore(FROM_BALANCE_SLOT, sub(balanceFrom, value))
        sstore(3, sub(sload(3), value))
        mstore(ptr, value)
        log3(ptr, 0x20, _TRANSFER_EVENT_SIG, from, 0)
      }
    }
  
    /**
     * @notice Returns the total supply of KIRU tokens in circulation
     * @dev This value decreases when tokens are burned and represents the current
     *      amount of KIRU tokens that exist
     * @return The total number of KIRU tokens in circulation
     */
    function totalSupply() public view returns (uint) {
        return _totalSupply;
    }

    /**
      * @notice Collects the cumulated withdraw fees and transfers them to the treasury.
      */
    function collect() external {
        address _TREASURY = TREASURY;
        assembly {
            let _cumulatedFees := sload(2)
            // set cumulated fees to 0
            sstore(2, 0)
            // transfer cumulated fees to treasury
            if iszero(call(gas(), _TREASURY, _cumulatedFees, 0, 0, 0, 0)) { revert (0, 0)}
        }
    }
    receive() external payable {}
}