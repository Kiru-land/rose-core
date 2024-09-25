// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

/**
  * @title Rose 🌹
  *
  * @author 5A6E55E
  *
  * @notice Rose is a ultra-efficient unified smart contract for the Rose token
  *         integrating an ultrasound market designed to push upwards volatility
  *         by design.
  *
  * @dev The Rose market is a continuous model composed of two reserves R₀ (ETH)
  *      and R₁ (ROSE). during a bonding curve interaction, x is the amount of
  *      ETH deposited to (or withdrawn from) the contract, while y is the Rose
  *      amount received (or spent).
  *
  *      The skew factor α(t) is a continuous function that dictates the
  *      evolution of the market's reserves asymmetry through time.
  *
  *      The slash-factor ϕ represents the fee factor taken from each withdraw
  *      operation.
  *
  * todo: fix Transfer events emitting wrong amount
  * todo: add collect(address token) external restricted
  */
contract Rose {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice The Rose blossoms.
      */
    string public constant name = "Rose";
    string public constant symbol = "ROSE";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;

    uint cumulatedFees;

    /**
      * @notice The initial skew factor α(0) scaled by 1e6
      */
    uint immutable ALPHA_INIT;
    /**
      * @notice The slash factor ϕ scaled by 1e6
      */
    uint immutable PHI_FACTOR;
    /**
      * @notice The initial reserve of ROSE R₁(0)
      */
    uint immutable R1_INIT;

    /**
      * @notice constant storage slots
      */
    uint constant BALANCE_OF_SLOT = 0;
    uint constant ALLOWANCE_SLOT = 1;
    uint constant CUMULATED_FEES_SLOT = 2;
    bytes32 immutable SELF_BALANCE_SLOT;
    bytes32 immutable TREASURY_BALANCE_SLOT;
    bytes32 immutable SALE_SLOT;

    /**
      * @notice event signatures
      */
    bytes32 constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 constant APPROVAL_EVENT_SIG = keccak256("Approval(address,address,uint256)");
    bytes32 constant BUY_EVENT_SIG = keccak256("Buy(address,uint256,uint256)");
    bytes32 constant SELL_EVENT_SIG = keccak256("Sell(address,uint256,uint256)");

    address public immutable TREASURY;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Buy(address indexed buyer, uint256 amount0In, uint256 amount1Out);
    event Sell(address indexed seller, uint256 amount1In, uint256 amount0Out);

    /**
      * @notice t=0 state
      */
    constructor(
      uint _alpha,
      uint _phi, 
      uint256 _supply,
      uint256 _r1Init, 
      uint256 _forSale, 
      uint256 _treasuryAllo, 
      uint256 _clawback,
      address _treasury
      ) payable {
        
        ALPHA_INIT = _alpha;
        PHI_FACTOR =  _phi;
        R1_INIT = _r1Init;
        TREASURY = _treasury;

        bytes32 _SELF_BALANCE_SLOT;
        bytes32 _SALE_SLOT;
        bytes32 _TREASURY_BALANCE_SLOT;

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, address())
            mstore(add(ptr, 0x20), BALANCE_OF_SLOT)
            _SELF_BALANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, _treasury)
            _TREASURY_BALANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, caller())
            _SALE_SLOT := keccak256(ptr, 0x40)
            if iszero(eq(add(add(add(_r1Init, _forSale), _treasuryAllo), _clawback), _supply)) { revert(0, 0) }
            sstore(_SELF_BALANCE_SLOT, _r1Init)
            sstore(_SALE_SLOT, add(_forSale, _clawback))
            sstore(_TREASURY_BALANCE_SLOT, _treasuryAllo)
        }

        SELF_BALANCE_SLOT = _SELF_BALANCE_SLOT;
        SALE_SLOT = _SALE_SLOT;
        TREASURY_BALANCE_SLOT = _TREASURY_BALANCE_SLOT;
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// Buy /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
             _____
           .'/L|__`.
          / =[_]O|` \
         |   _  |   |
         ;  (_)  ;  |
          '.___.' \  \
           |     | \  `-.
          |    _|  `\    \
           _./' \._   `-._\
         .'/     `.`.   '_.-.
     
      title: The Strategist
     
      @notice Long ago, the Strategist was known as the Oracle of the
              Lost Era, a being of great wisdom who guided civilizations
              for centuries. After the collapse of the old world, the
              Oracle withdrew from the affairs of mortals, becoming the
              Strategist, overseeing the rise of the asset born from the
              ashes of forgotten realms. The Strategist remains a silent
              guardian, weaving fate and fortune into the flow of trade.
              
               ::::                                       °      ::::
            :::        .           ------------             .        :::
           ::               °     |...       ° | - - - - ◓             ::
           :             o        |   ...  .   |                        :
           ::          .          |  °   ...   |                       ::
            :::         ◓ - - - - |   .     ...|                     :::
               ::::                ------------                  ::::
    */


    /**
      * @notice Deposit is the entry point for entering the Rose bonding-curve
      *         upon receiving ETH, the rose contract computes the amount out `y`
      *         using the [skew trading function](https://github.com/RedRoseMoney/Rose).
      *         The result is an asymmetric bonding curve that can optimise for price
      *         appreciation, biased by the skew factor α(t).
      *
      * @dev The skew factor α(t) is a continuous function of the markets reserves
      *      computed as α(t) = 1 − α(0) ⋅ (R₁(0) / R₁(t))
      *      with R₁(0) being the initial reserve of ROSE at construction and R₁(t)
      *      the reserve of ROSE at time t.
      *      α(t) is simulating a LP withdraw operation right before the buy. In this
      *      analogy, the skew factor α(t) represents the fraction of the current
      *      reserves that the LP is withdrawing.
      *      The skew factor is then used to compute the new reserves (R₀′, R₁′) and
      *      the amount out `y` 
      *      
      *         αR₁′ = αK / αR₀ + x
      *         y    = αR₁ - αR₁′
      *
      *      where αK = αR₀ * αR₁
      *      
      *      After computing the swapped amount `y` on cut reserves, the LP provides the
      *      maximum possible liquidity from the withdrawn amount at the new market rate.
      */
    function deposit(uint outMin) external payable returns (uint) {
        uint _ALPHA_INIT = ALPHA_INIT;
        uint _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        bytes32 _TREASURY_BALANCE_SLOT = TREASURY_BALANCE_SLOT;
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), BALANCE_OF_SLOT)
            let CALLER_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * x  = msg.value
             * R₀ = token₀ reserves
             * R₁ = token₁ reserves
             */
            let x := callvalue()
            let r0 := sub(sub(selfbalance(), sload(CUMULATED_FEES_SLOT)), callvalue())
            let r1 := sload(_SELF_BALANCE_SLOT)
            /*
             * Compute the skew factor α(t)
             *
             *  α(t) = 1 − α(0) ⋅ (R₁(0) / R₁(t))
             */
            let r1InitR1Ratio := div(mul(r1, 1000000), _R1_INIT)
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            let alpha := sub(1000000, inverseAlpha)
            /*
             * Compute the new reserves (R₀′, R₁′) and the amount out y
             *
             *  αR₀′    = αR₀ + x
             *  αR₁′    = (αR₀ * αR₁) / αR₀′
             *  y       = αR₁ - αR₁′
             *  R₀′     = R₀ + x
             *  R₁′     = (αR₁′ / αR₀′) * R₀′
             *  Δtoken₁ = (R₀ * R₁) / R₀′ - R₁′
             */
            let alphaR0 := div(mul(alpha, r0), 1000000)
            let alphaR1 := div(mul(alpha, r1), 1000000)
            let alphaR0Prime := add(alphaR0, x)
            let alphaR1Prime := div(mul(alphaR0, alphaR1), alphaR0Prime)
            let y := sub(alphaR1, alphaR1Prime)
            let r0Prime := add(r0, x)
            let r1Prime := div(mul(div(mul(alphaR1Prime, 1000000), alphaR0Prime), r0Prime), 1000000)
            let deltaToken1 := sub(div(mul(r0, r1), r0Prime), r1Prime)
            /*
             * Ensures that the amount out y is >= outMin
             */
            // Question: C'est pas plutot lt(outMin, y) ? Si l'outMin est inferieur à ce que le constant product donne, on revert.
            if gt(outMin, y) {revert(0, 0)}
            /*
             * Update the market reserves to (R₀′, R₁′) then update balances
             */
            sstore(_SELF_BALANCE_SLOT, r1Prime)
            let balanceOfCaller := sload(CALLER_BALANCE_SLOT)
            sstore(CALLER_BALANCE_SLOT, add(balanceOfCaller, y))
            let balanceOfTreasury := sload(_TREASURY_BALANCE_SLOT)
            sstore(_TREASURY_BALANCE_SLOT, add(balanceOfTreasury, deltaToken1))
            /*
             * emit Transfer event
             */
            mstore(ptr, address())
            mstore(add(ptr, 0x20), caller())
            mstore(add(ptr, 0x40), y)
            log3(ptr, 0x60, _TRANSFER_EVENT_SIG, address(), caller())
            /*
             * return amount out
             */
            mstore(ptr, y)
            return(ptr, 0x20)
        }
    }

    function withdraw(uint value, uint outMin) external payable returns (uint) {
        uint _PHI_FACTOR = PHI_FACTOR;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            let from := caller()
            mstore(ptr, from)
            mstore(add(ptr, 0x20), BALANCE_OF_SLOT)
            let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
            /*
             * check that caller has enough funds
             */
            let balanceFrom := sload(FROM_BALANCE_SLOT)
            if lt(balanceFrom, value) { revert(0, 0) }
            let _cumulatedFees := sload(CUMULATED_FEES_SLOT)
            /*
             *  load market's reserves (R₀, R₁)
             */
            let r0 := sub(selfbalance(), _cumulatedFees)
            let r1 := sload(_SELF_BALANCE_SLOT)
            let y := value
            /*
             * Only allow sell orders under 5% of Rose's liquidity
             * to prevent divergence.
             */
            if gt(y, div(r1,20)) { revert(0, 0) }
            /*
             * the rose sent is sold for ETH using the CP formula:
             *     y = (R₁ - K / (R₀ + x)) * ϕfactor
             *
             *  R₁′ = R₁ + y
             *  R₀′ = K / R₁′
             *  x = R₁ - R₁′
             *  ϕ = x * ϕfactor
             */
            let r1prime := add(r1, y)
            let x := sub(r0, div(mul(r0, r1), r1prime))
            let phi := div(mul(x, _PHI_FACTOR), 1000000)
            let xOut := sub(x, phi)
            /*
             * Ensures that the amount out xOut >= outMin
             */
            // Question: C'est pas plutot lt(outMin, y) ? Si l'outMin est inferieur à ce que le constant product donne, on revert.
            if gt(outMin, xOut) {revert(0, 0)}
            /*
             * increment cumulated fees by ϕ
             */
            sstore(CUMULATED_FEES_SLOT, add(_cumulatedFees, phi))
            /*
             * Transfer x-ϕ ETH to the seller's address
             */
            if iszero(call(gas(), from, xOut, 0, 0, 0, 0)) { revert(0, 0) }
            /*
             * decrease sender's balance
             */
            sstore(FROM_BALANCE_SLOT, sub(balanceFrom, value))
            /*
             * increment recipient's balance
             */
            sstore(_SELF_BALANCE_SLOT, add(sload(_SELF_BALANCE_SLOT), value))
            /*
             * emit Transfer event
             */
            mstore(ptr, from)
            mstore(add(ptr, 0x20), address())
            mstore(add(ptr, 0x40), value)
            log3(ptr, 0x60, _TRANSFER_EVENT_SIG, from, address())
            /*
             * return amount out
             */
            mstore(ptr, xOut)
            return(ptr, 0x20)
        }
    }

    function quoteDeposit(uint value) public view returns (uint) {
        uint _ALPHA_INIT = ALPHA_INIT;
        uint _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            let r0 := sub(selfbalance(), sload(CUMULATED_FEES_SLOT))
            let r1 := sload(_SELF_BALANCE_SLOT)
            let r1InitR1Ratio := div(mul(r1, 1000000), _R1_INIT)
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

    function quoteWithdraw(uint value) public view returns (uint) {
        uint _PHI_FACTOR = PHI_FACTOR;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            let r0 := sub(selfbalance(), sload(CUMULATED_FEES_SLOT))
            let r1 := sload(_SELF_BALANCE_SLOT)
            let r1prime := add(r1, value)
            let x := sub(r0, div(mul(r0, r1), r1prime))
            let phi := div(mul(x, _PHI_FACTOR), 1000000)
            let xOut := sub(x, phi)
            mstore(ptr, xOut)
            return(ptr, 0x20)
        }
    }

    /**
      * @notice Collects the cumulated withdraw fees and transfers them to the treasury.
      */
    function collect() external {
        address _TREASURY = TREASURY;
        assembly {
            let _cumulatedFees := sload(CUMULATED_FEES_SLOT)
            // set cumulated fees to 0
            sstore(CUMULATED_FEES_SLOT, 0)
            // transfer cumulated fees to treasury
            if iszero(call(gas(), _TREASURY, _cumulatedFees, 0, 0, 0, 0)) { revert (0, 0)}
        }
    }

    /**
      * @notice Returns the market's reserves and the skew factor α(t).
      *
      * @return r0 The balance of the ROSE contract.
      *
      * @return r1 The balance of the ROSE contract.
      *
      * @return alpha The skew factor α(t).
      */
    function getState() public view returns (uint r0, uint r1, uint alpha) {
        uint _ALPHA_INIT = ALPHA_INIT;
        uint _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            r0 := sub(selfbalance(), sload(CUMULATED_FEES_SLOT))
            r1 := sload(_SELF_BALANCE_SLOT)
            let r1InitR1Ratio := div(mul(r1, 1000000), _R1_INIT)
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            alpha := sub(1000000, inverseAlpha)
        }
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// ERC20 ////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
                , .-.-,_,
                )`-.>'` (
               /     `\  |
               |       | |
                \     / /
                `=(\ /.=`
                 `-;`.-'
                   `)|     ,
                    ||  .-'|
                  ,_||  \_,/
            ,      \|| .'
            |\|\  , ||/
           ,_\` |/| |Y_,
            '-.'-._\||/
               >_.-`Y|
               `|   ||
                    ||  
                    ||
                    ||
     
      title:  The Rose token
     
      @notice The ultrasound Rose token.
    */


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
            mstore(ptr, to)
            mstore(add(ptr, 0x20), BALANCE_OF_SLOT)
            let TO_BALANCE_SLOT := keccak256(ptr, 0x40)
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
            mstore(ptr, owner)
            mstore(add(ptr, 0x20), ALLOWANCE_SLOT)
            let OWNER_ALLOWANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, spender)
            mstore(add(ptr, 0x20), OWNER_ALLOWANCE_SLOT)
            let SPENDER_ALLOWANCE_SLOT := keccak256(ptr, 0x40)
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
      * @param value The amount of rose to transfer.
      *
      * @return true
      */
    function transfer(address to, uint256 value) public returns (bool) {
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            let from := caller()
            mstore(ptr, from)
            mstore(add(ptr, 0x20), BALANCE_OF_SLOT)
            let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, to)
            let TO_BALANCE_SLOT := keccak256(ptr, 0x40)
            // check that caller has enough funds
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
            mstore(ptr, from)
            mstore(add(ptr, 0x20), to)
            mstore(add(ptr, 0x40), value)
            log3(ptr, 0x60, _TRANSFER_EVENT_SIG, from, to)
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
      * @param value The amount of rose to transfer.
      *
      * @return true
      */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            let spender := caller()
            mstore(ptr, from)
            mstore(add(ptr, 0x20), BALANCE_OF_SLOT)
            let FROM_BALANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, to)
            let TO_BALANCE_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, from)
            mstore(add(ptr, 0x20), ALLOWANCE_SLOT)
            let ALLOWANCE_FROM_SLOT := keccak256(ptr, 0x40)
            mstore(ptr, spender)
            mstore(add(ptr, 0x20), ALLOWANCE_FROM_SLOT)
            let ALLOWANCE_FROM_CALLER_SLOT := keccak256(ptr, 0x40)
            // check that msg.sender has sufficient allowance
            let __allowance := sload(ALLOWANCE_FROM_CALLER_SLOT)
            if lt(__allowance, value) { revert(0, 0) }
            // Reduce the spender's allowance
            sstore(ALLOWANCE_FROM_CALLER_SLOT, sub(__allowance, value))
            // check that from has enough funds
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
            mstore(ptr, from)
            mstore(add(ptr, 0x20), to)
            mstore(add(ptr, 0x40), value)
            log3(ptr, 0x60, _TRANSFER_EVENT_SIG, from, to)
            /*
             * Return true
             */
            mstore(ptr, 1)
            return(ptr, 0x20)
        }
    }

    function approve(address to, uint256 value) public returns (bool) {
        bytes32 _APPROVAL_EVENT_SIG = APPROVAL_EVENT_SIG;
        assembly {
            let owner := caller()
            let ptr := mload(0x40)
            mstore(ptr, owner)
            mstore(add(ptr, 0x20), ALLOWANCE_SLOT)
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
            mstore(ptr, owner)
            mstore(add(ptr, 0x20), to)
            mstore(add(ptr, 0x40), value)
            log3(ptr, 0x60, _APPROVAL_EVENT_SIG, owner, to)
            /*
             * Return true
             */
            mstore(ptr, 1)
            return(ptr, 0x20)
        }
    }

    receive() external payable {}
}
