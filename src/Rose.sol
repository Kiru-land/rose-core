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
  * @notice Rose is an efficient contract for the Rose tokenized bonding curve.
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
  * @dev Jita market, the bonding-curve of the Rose token, executes buys and
  *      sells with different dynamics, exploiting this assymetry to optimize
  *      for price volatility on buys and deep liquidity on sells.
  *      Driven by the skew factor α(t), Jita binds price appreciation to
  *      uniform volume.
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

    mapping(address => uint) private _balanceOf;
    mapping(address => mapping(address => uint)) private _allowance;

    /**
      * @notice The cumulated native fees
      */
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

    address public immutable TREASURY;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

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
        /*
         * Initialize constant state variables
         */
        ALPHA_INIT = _alpha;
        PHI_FACTOR =  _phi;
        R1_INIT = _r1Init;
        TREASURY = _treasury;
        /*
         * Mint market liquidity and supply
         */
        _balanceOf[msg.sender] = _r1Init;
        _balanceOf[_treasury] = _supply - _r1Init;
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
      *               This parameter introduces slippage bounds for the trade.
      *
      * @return y The amount of ROSE received.
      */
    function deposit(uint outMin) external payable returns (uint y) {
        /*
         * x  = msg.value
         * R₀ = token₀ reserves
         * R₁ = token₁ reserves
         */
        uint x = msg.value;
        uint r0 = address(this).balance - cumulatedFees;
        uint r1 = balanceOf(msg.sender);
        /*
         * Compute the skew factor α(t)
         */
        uint InverseAlpha = ALPHA_INIT * (r1 * 1e6 / R1_INIT) / 1e6;
        uint alpha = 1e6 - InverseAlpha;
        /*
         * Compute the new reserves (R₀′, R₁′) and the amount out y
         *
         * α-reserves are reserves cut by the skew factor α(t)
         */
        uint alphaR0 = alpha * r0 / 1e6;
        uint alphaR1 = alpha * r1 / 1e6;
        /*
         * The new α-reserve 0, increased by x
         *
         * αR₀′ = αR₀ + x
         */
        uint alphaR0Prime = alphaR0 + x;
        /*
         * The new α-reserve 1, computed as the constant product of the α-reserves
         *
         * αR₁′ = (αR₀ * αR₁) / αR₀′
         */
        uint alphaR1Prime = alphaR0 * alphaR1 / alphaR0Prime;
        /*
         * The amount out y, computed as the difference between the initial α-reserve 1 and the new α-reserve 1
         *
         * y = αR₁ - αR₁′
         */
        y = alphaR1 - alphaR1Prime;
        /*
         * The new actual reserve 0, increased by x
         *
         * R₀′ = R₀ + x
         */
        uint r0Prime = r0 + x;
        /*
         * The new actual reserve 1, computed as new reserve 0 * α-ratio
         * where α-ratio: αR₁′ / αR₀′
         *
         * R₁′ = (αR₁′ / αR₀′) * R₀′
         */
        uint r1Prime = (alphaR1Prime * 1e6) / alphaR0Prime * r0Prime / 1e6;
        /*
         * Delta between constant product of actual reserves and new reserve 1
         *
         * ΔR₁ = R₀ * R₁ / R₀′ - R₁′
         */
        uint deltaToken1 = r0 * r1 / r0Prime - r1Prime;
        /*
         * Ensures that the amount out is within slippage bounds
         */
        if (outMin > y) revert("Slippage bounds");
        /*
         * Update the market reserves to (R₀′, R₁′) then update balances
         */
        _balanceOf[msg.sender] += y;
        _balanceOf[TREASURY] += deltaToken1;

        emit Transfer(address(this), msg.sender, y);
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// Sell /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Withdraws ETH from Jita's bonding curve
      *
      * @dev This contracts operate at low-level and does not require sending funds 
      *      before withdrawing, it instead requires the caller to have enough
      *      balance, then balance slots gets updated accordingly.
      *
      * @param value The amount of ETH to withdraw.
      *
      * @param outMin The minimum amount of ETH to receive.
      *               This parameter introduces slippage bounds for the trade.
      *
      * @return xOut The amount of ETH received.
      */
    function withdraw(uint value, uint outMin) external payable returns (uint xOut) {
        uint phi = PHI_FACTOR;
        /*
         * load market's reserves (R₀, R₁)
         */
        uint r0 = address(this).balance - cumulatedFees;
        uint r1 = balanceOf(address(this));
        /*
         * Only allow sell orders under 5% of Rose's liquidity
         * to prevent divergence.
         */
        if (value >= r1 / 20) revert("Amount too large");
        /*
         * the rose sent is sold for ETH using the CP formula, minus the ϕ penalty:
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
        uint r1Prime = r1 + value;
        /*
         * Compute the raw amount out x
         *
         * x = R₀ - (R₀ * R₁) / R₁′
         */
        uint x = r0 - (r0 * r1 / r1Prime);
        /*
         * Compute the withdrawal fee ϕ
         *
         * ϕ = x * ϕfactor
         */
        uint fee = x * phi / 1e6;
        /*
         * Compute the amount out xOut
         *
         * xOut = x - ϕ
         */
        xOut = x - fee;
        /*
         * Ensures that the amount out is within slippage bounds
         */
        if (outMin > xOut) revert("Slippage bounds");
        /*
         * Increment cumulated fees by ϕ
         */
        cumulatedFees += fee;
        /*
         * Update balances
         */
        _balanceOf[msg.sender] -= value;
        _balanceOf[address(this)] += value;
        /*
         * Transfer x-ϕ ETH to the seller's address
         */
        (bool success, ) = msg.sender.call{value: xOut}("");
        if (!success) revert("Transfer failed");

        emit Transfer(msg.sender, address(this), value);
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Quote /////////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Computes the amount of ROSE received for a given amount of ETH deposited
      *         given the current market reserves.
      *
      * @param value The amount of ETH to deposit.
      *
      * @return The amount of ROSE received.
      */
    function quoteDeposit(uint value) public view returns (uint) {
        uint r0 = address(this).balance - cumulatedFees;
        uint r1 = balanceOf(address(this));
        uint r1InitR1Ratio = r1 * 1e6 / R1_INIT;
        uint inverseAlpha = ALPHA_INIT * r1InitR1Ratio / 1e6;
        uint alpha = 1e6 - inverseAlpha;
        uint alphaR0 = alpha * r0 / 1e6;
        uint alphaR1 = alpha * r1 / 1e6;
        uint alphaR0Prime = alphaR0 + value;
        uint alphaR1Prime = alphaR0 * alphaR1 / alphaR0Prime;
        return alphaR1 - alphaR1Prime;
    }

    /**
      * @notice Computes the amount of ETH received for a given amount of ROSE withdrawn
      *         given the current market reserves.
      *
      * @param value The amount of ROSE to withdraw.
      *
      * @return The amount of ETH received.
      */
    function quoteWithdraw(uint value) public view returns (uint) {
        uint r0 = address(this).balance - cumulatedFees;
        uint r1 = balanceOf(address(this));
        uint r1Prime = r1 + value;
        uint x = r0 - (r0 * r1 / r1Prime);
        uint phi = x * PHI_FACTOR / 1e6;
        return x - phi;
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
    function getState() public view returns (uint r0, uint r1, uint alpha) {
        r0 = address(this).balance - cumulatedFees;
        r1 = balanceOf(address(this));
        uint r1InitR1Ratio = r1 * 1e6 / R1_INIT;
        uint inverseAlpha = ALPHA_INIT * r1InitR1Ratio / 1e6;
        alpha = 1e6 - inverseAlpha;
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
     function balanceOf(address to) public view returns (uint _balance) {
        _balance = _balanceOf[to];
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
        __allowance = _allowance[owner][spender];
     }

    /**
      * @notice ERC20 transfer function
      *
      * @dev The caller must have sufficient balance to transfer the specified amount.
      *
      * @param to The address to transfer to.
      *
      * @param value The amount of rose to transfer.
      *
      * @return true
      */
    function transfer(address to, uint value) public returns (bool) {
        _balanceOf[msg.sender] -= value;
        _balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
      * @notice ERC20 transferFrom function
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
    function transferFrom(address from, address to, uint value) public returns (bool) {
        if (_balanceOf[from] < value) revert("Insufficient balance");
        if (_allowance[from][msg.sender] < value) revert("Insufficient allowance");
        _balanceOf[from] -= value;
        _balanceOf[to] += value;
        _allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }

    /**
      * @notice ERC20 approve function
      *
      * @param to The address to approve.
      *
      * @param value The amount of rose to approve.
      *
      * @return true
      */
    function approve(address to, uint value) public returns (bool) {
        _allowance[msg.sender][to] = value;
        emit Approval(msg.sender, to, value);
        return true;
    }
    
    /**
      * @notice Collects the cumulated withdraw fees and transfers them to the treasury.
      */
    function collect() external {
        uint cumulated = cumulatedFees;
        cumulatedFees = 0;
        (bool success, ) = TREASURY.call{value: cumulated}("");
        if (!success) revert("Transfer failed");
    }

    receive() external payable {}
}
