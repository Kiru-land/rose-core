// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 


//////////////////////////////////////////////////////////////
//////////////////////// Interfaces //////////////////////////
//////////////////////////////////////////////////////////////

interface IKiru {
    function deposit(uint) external payable;
}

interface IERC20 {
    function transfer(address, uint) external;
    function balanceOf(address) external view returns (uint);
}

/**
  * @title EvilKiru
  */
contract EvilKiru {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    /*
     * ERC20
     */
    string public constant name = "Evil Kiru";
    string public constant symbol = "eKIRU";
    uint8 public constant decimals = 18;

    mapping(address => uint) private _balanceOf;

    mapping(address => mapping(address => uint)) private _allowance;

    uint256 _totalSupply;

    /*
     * @notice The parameter alpha
     *         Alpha is the global parameter that controls the amount
     *         of tokens burned per unit of Kiru deposited/withdrawn.
     */
    uint alpha;

    address constant KIRU = 0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2;

    //////////////////////////////////////////////////////////////
    /////////////////////////// Events ///////////////////////////
    //////////////////////////////////////////////////////////////

    event Approval(address indexed owner, address indexed spender, uint amount);
    event Transfer(address indexed from, address indexed to, uint amount);
    event Deposit(address indexed from, uint x, uint y);
    event Withdraw(address indexed to, uint x, uint y);

    //////////////////////////////////////////////////////////////
    //////////////////////// Constructor /////////////////////////
    //////////////////////////////////////////////////////////////

    constructor(uint _alpha, string memory _name, string memory _symbol) {
        alpha = _alpha;
        name = _name;
        symbol = _symbol;
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Deposit ///////////////////////////
    //////////////////////////////////////////////////////////////

    function deposit(uint outMin0, uint outMin1) external payable {
        uint kiruBalance = IKiru(KIRU).balanceOf(address(this));
        /*
         * Deposit into Kiru
         */
        IKiru(KIRU).deposit{value: msg.value}(outMin0);
        /*
         * Swap Kiru to EvilKiru
         */
        uint x = IKiru(KIRU).balanceOf(address(this)) - kiruBalance;
        uint r0 = kiruBalance - x;
        uint r1 = _balanceOf[address(this)];
        uint phi = msg.value / alpha;
        uint r0Prime = r0 + x;
        uint r1Prime = r0 * r1 / r0Prime - phi;
        uint y = r1 - r1Prime;
        require(y >= outMin1, "slippage bounds reached");
        _balanceOf[address(this)] -= phi;
        _balanceOf[address(0)] += phi;
        _totalSupply -= phi;
        _balanceOf[address(this)] = r1Prime;
        _balanceOf[msg.sender] += y;
        emit Deposit(msg.sender, x, y);
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Withdraw //////////////////////////
    //////////////////////////////////////////////////////////////

    function withdraw(uint y, uint outMin0, uint outMin1) external {
        uint r0 = IERC20(KIRU).balanceOf(address(this));
        uint r1 = _balanceOf[address(this)];
        uint r1Prime = r1 + y;
        uint r0Prime = r0 * r1 / r1Prime;
        uint x = r0Prime - r0;
        require(x >= outMin0, "slippage bounds reached");
        _balanceOf[msg.sender] -= y;
        _balanceOf[address(this)] = r1Prime;
        x -= x / alpha;
        IKiru(KIRU).withdraw(x, outMin1);
        emit Withdraw(msg.sender, x, y);
    }

    //////////////////////////////////////////////////////////////
    /////////////////////////// ERC20 ////////////////////////////
    //////////////////////////////////////////////////////////////

    function balanceOf(address account) external view returns (uint) {
        return _balanceOf[account];
    }

    function allowance(address owner, address spender) external view returns (uint) {
        return _allowance[owner][spender];
    }

    function approve(address spender, uint amount) external {
        _allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function transfer(address to, uint amount) external {
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint amount) external {
        _allowance[from][msg.sender] -= amount;
        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function burn(uint amount) external {
        _balanceOf[msg.sender] -= amount;
        _balanceOf[address(0)] += amount;
        _totalSupply -= amount;
    }
}
