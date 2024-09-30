// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

/**
  * @title 🌹
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
  * @author 5A6E55E
  *
  * @notice Rose is an efficient contract for the Rose token and it's canonical
  *         market Jita.
  *         Unification under a single contract allows for precise control over
  *         the market-making strategy, fully automated.
  *
  *            ::::                                       °      ::::
  *         :::        .           ------------             .        :::
  *        ::               °     |...       ° | - - - - ◓             ::
  *        :             o        |   ...  .   |                        :
  *        ::          .          |  °   ...   |                       ::
  *         :::         ◓ - - - - |   .     ...|                     :::
  *            ::::                ------------                  ::::
  *
  * @dev Jita market has unlimited power and can treat buys and sells in an
  *      asymmetric way, exploiting this assymetry to optimise for price
  *      volatility on buys and deep liquidity on sells, and binding price
  *      appreciation to uniform volume.
  *      This contract leverages assembly to bypass solidity's overhead and
  *      enable efficient market-making.
  *
  * todo: fix Transfer events emitting wrong amount
  * todo: add collect(address token) external restricted
  */
contract Rose {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      *             , .-.-,_,
      *             )`-.>'` (
      *            /     `\  |
      *            |       | |
      *             \     / /
      *             `=(\ /.=`
      *              `-;`.-'
      *                `)|     ,
      *                 ||  .-'|
      *               ,_||  \_,/
      *         ,      \|| .'
      *         |\|\  , ||/
      *        ,_\` |/| |Y_,
      *         '-.'-._\||/
      *            >_.-`Y|
      *            `|   ||
      *                 ||  
      *                 ||
      *                 ||
      *                 ||
      *
      * @notice The Rose blossoms.
      */
    string public constant name = "Rose";
    string public constant symbol = "ROSE";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _balanceOf; // slot 0

    mapping(address => mapping(address => uint256)) private _allowance; // slot 1

    uint256 cumulatedFees; // slot 2

    /**
      * @notice The initial skew factor α(0) scaled by 1e6
      */
    uint256 immutable ALPHA_INIT;
    /**
      * @notice The slash factor ϕ scaled by 1e6
      */
    uint256 immutable PHI_FACTOR;
    /**
      * @notice The initial reserve of ROSE R₁(0)
      */
    uint256 immutable R1_INIT;

    /**
      * @notice constant storage slots
      */
    bytes32 immutable SELF_BALANCE_SLOT;
    bytes32 immutable TREASURY_BALANCE_SLOT;

    /**
      * @notice event signatures
      */
    bytes32 constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 constant APPROVAL_EVENT_SIG = keccak256("Approval(address,address,uint256)");

    address public immutable TREASURY;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    //////////////////////////////////////////////////////////////
    //////////////////////// Constructor /////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice t=0 state
      */
    constructor(
      uint256 _alpha,
      uint256 _phi, 
      uint256 _r1Init, 
      uint256 _supply,
      address _treasury
      ) payable {
        ALPHA_INIT = _alpha;
        PHI_FACTOR =  _phi;
        R1_INIT = _r1Init;
        TREASURY = _treasury;

        bytes32 _SELF_BALANCE_SLOT;
        bytes32 _LAUNCH_SLOT;
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
             * Load balanceOf[msg.sender] slot
             */
            mstore(ptr, caller())
            _LAUNCH_SLOT := keccak256(ptr, 0x40)
            /*
             * Set the initial balances
             */
            sstore(_SELF_BALANCE_SLOT, _r1Init)
            sstore(_LAUNCH_SLOT, sub(_supply, _r1Init))
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
      *      R₁ = Rose reserves
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
      * @notice Deposit is the entry point for entering the Rose bonding-curve
      *         upon receiving ETH, the rose contract computes the amount out `y`
      *         using the [skew trading function](https://github.com/RedRoseMoney/Rose).
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
      * @param outMin The minimum amount of ROSE to receive.
      *               This parameter introduces slippage bounds to the trade.
      *
      * @return The amount of ROSE received.
      */
    function deposit(uint256 outMin) external payable returns (uint256) {
        uint256 _ALPHA_INIT = ALPHA_INIT;
        uint256 _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        bytes32 _TREASURY_BALANCE_SLOT = TREASURY_BALANCE_SLOT;
        bytes32 _TRANSFER_EVENT_SIG = TRANSFER_EVENT_SIG;
        assembly {
            let ptr := mload(0x40)
            /*
             * Load balanceOf[msg.sender] slot
             */
            mstore(ptr, caller())
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
             * Compute the skew factor α(t)
             */
            let r1InitR1Ratio := div(mul(r1, 1000000), _R1_INIT)
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            let alpha := sub(1000000, inverseAlpha)
            /*
             * Compute the new reserves (R₀′, R₁′) and the amount out y
             *
             * α-reserves are reserves cut by the skew factor α(t)
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
             * R₁′ = (αR₁′ / αR₀′) * R₀′
             */
            let r1Prime := div(mul(div(mul(alphaR1Prime, 1000000), alphaR0Prime), r0Prime), 1000000)
            /*
             * Delta between constant product of actual reserves and new reserve 1
             *
             * ΔR₁ = R₀ * R₁ / R₀′ - R₁′
             */
            let deltaToken1 := sub(div(mul(r0, r1), r0Prime), r1Prime)
            /*
             * Ensures that the amount out is within slippage bounds
             */
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

    //////////////////////////////////////////////////////////////
    /////////////////////////// Sell /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Withdraws ETH from Jita's bonding curve
      *
      * @dev This contracts operate at low-level and does not require sending funds 
      *      before withdrawing, it instead only requires the caller to have enough
      *      balance, then balance slots are updated accordingly.
      *
      * @param value The amount of ETH to withdraw.
      * @param outMin The minimum amount of ETH to receive.
      * @return The amount of ETH received.
      */
    function withdraw(uint256 value, uint256 outMin) external payable returns (uint256) {
        uint256 _PHI_FACTOR = PHI_FACTOR;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
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
             * check that caller has enough funds
             */
            let balanceFrom := sload(FROM_BALANCE_SLOT)
            if lt(balanceFrom, value) { revert(0, 0) }
            let _cumulatedFees := sload(2)
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
             *
             *     y = (R₁ - K / (R₀ + x)) * ϕfactor
             *
             * where:
             *
             *    y: Rose amount in
             *    x: Eth amount out
             *    K: R₀ * R₁
             *    ϕfactor: withdrawal penalty factor
             *
             * Compute the new reserve 1 by adding the amount out y
             * 
             * R₁′ = R₁ + y
             */
            let r1prime := add(r1, y)
            /*
             * Compute the raw amount out x
             *
             * x = R₀ - (R₀ * R₁) / R₁′
             */
            let x := sub(r0, div(mul(r0, r1), r1prime))
            /*
             * Compute the withdrawal fee ϕ
             *
             * ϕ = x * ϕfactor
             */
            let phi := div(mul(x, _PHI_FACTOR), 1000000)
            /*
             * Compute the amount out xOut
             *
             * xOut = x - ϕ
             */
            let xOut := sub(x, phi)
            /*
             * Ensures that the amount out is within slippage bounds
             */
            if gt(outMin, xOut) {revert(0, 0)}
            /*
             * increment cumulated fees by ϕ
             */
            sstore(2, add(_cumulatedFees, phi))
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

    //////////////////////////////////////////////////////////////
    ////////////////////////// Quote /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Computes the amount of ROSE received for a given amount of ETH deposited.
      *
      * @param value The amount of ETH to deposit.
      *
      * @return The amount of ROSE received.
      */
    function quoteDeposit(uint256 value) public view returns (uint256) {
        uint256 _ALPHA_INIT = ALPHA_INIT;
        uint256 _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            let r0 := sub(selfbalance(), sload(2))
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

    /**
      * @notice Computes the amount of ETH received for a given amount of ROSE withdrawn.
      *
      * @param value The amount of ROSE to withdraw.
      *
      * @return The amount of ETH received.
      */
    function quoteWithdraw(uint256 value) public view returns (uint256) {
        uint256 _PHI_FACTOR = PHI_FACTOR;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            let ptr := mload(0x40)
            let r0 := sub(selfbalance(), sload(2))
            let r1 := sload(_SELF_BALANCE_SLOT)
            let r1prime := add(r1, value)
            let x := sub(r0, div(mul(r0, r1), r1prime))
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
      * @return r0 The balance of the ROSE contract.
      *
      * @return r1 The balance of the ROSE contract.
      *
      * @return alpha The skew factor α(t).
      */
    function getState() public view returns (uint256 r0, uint256 r1, uint256 alpha) {
        uint256 _ALPHA_INIT = ALPHA_INIT;
        uint256 _R1_INIT = R1_INIT;
        bytes32 _SELF_BALANCE_SLOT = SELF_BALANCE_SLOT;
        assembly {
            r0 := sub(selfbalance(), sload(2))
            r1 := sload(_SELF_BALANCE_SLOT)
            let r1InitR1Ratio := div(mul(r1, 1000000), _R1_INIT)
            let inverseAlpha := div(mul(_ALPHA_INIT, r1InitR1Ratio), 1000000)
            alpha := sub(1000000, inverseAlpha)
        }
    }

    //////////////////////////////////////////////////////////////
    //////////////////////////// ROSE ////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Returns the balance of the specified address.
      *
      * @param to The address to get the balance of.
      *
      * @return _balance The balance of the specified address.
      */
     function balanceOf(address to) public view returns (uint256 _balance) {
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
     function allowance(address owner, address spender) public view returns (uint256 __allowance) {
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
      * @param value The amount of rose to transfer.
      *
      * @return true
      */
    function transfer(address to, uint256 value) public returns (bool) {
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
