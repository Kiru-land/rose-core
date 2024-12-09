// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 


//////////////////////////////////////////////////////////////
//////////////////////// Interfaces //////////////////////////
//////////////////////////////////////////////////////////////

interface IKiru {
    function deposit(uint) external payable;
    function withdraw(uint, uint) external;
    function quoteDeposit(uint) external view returns (uint);
    function quoteWithdraw(uint) external view returns (uint);
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

    address public constant KIRU = 0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2;
    address public treasury = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

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

    constructor(uint _alpha, uint256 _supply) {
        alpha = _alpha;
        uint256 treasuryShare = _supply / 10;
        _balanceOf[treasury] = treasuryShare;
        _balanceOf[address(this)] = _supply - treasuryShare;
        _totalSupply = _supply;
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Deposit ///////////////////////////
    //////////////////////////////////////////////////////////////

    function deposit(uint outMin0, uint outMin1) external payable {
        uint kiruBalance = IERC20(KIRU).balanceOf(address(this));
        /*
         * Deposit into Kiru
         */
        IKiru(KIRU).deposit{value: msg.value}(outMin0);
        /*
         * Swap Kiru to EvilKiru
         */
        uint kiruBalanceAfter = IERC20(KIRU).balanceOf(address(this));
        uint x = kiruBalanceAfter - kiruBalance;
        uint r0 = kiruBalanceAfter - x;
        uint r1 = _balanceOf[address(this)];
        uint phi = msg.value / alpha;
        uint r0Prime = r0 + x;
        uint r1Prime = r0 * r1 * 1e18 / r0Prime / 1e18 - phi;
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
        uint r0Prime = r0 * r1 * 1e18 / r1Prime / 1e18;
        uint x = r0 - r0Prime;
        x -= x / alpha;
        require(x >= outMin0, "slippage bounds reached");
        _balanceOf[msg.sender] -= y;
        _balanceOf[address(this)] = r1Prime;
        uint balanceBefore = address(this).balance;
        IKiru(KIRU).withdraw(x, outMin1);
        uint balanceAfter = address(this).balance;
        uint native = balanceAfter - balanceBefore;
        (bool success, ) = msg.sender.call{value: native}("");
        require(success, "failed to send native");
        emit Withdraw(msg.sender, y, native);
    }


    //////////////////////////////////////////////////////////////
    ////////////////////////// Quote /////////////////////////////
    //////////////////////////////////////////////////////////////

    function quoteDeposit(uint value) external view returns (uint x, uint y) {
        x = IKiru(KIRU).quoteDeposit(value);
        uint r0 = IERC20(KIRU).balanceOf(address(this));
        uint r1 = _balanceOf[address(this)];
        uint phi = value / alpha;
        uint r0Prime = r0 + x;
        uint r1Prime = r0 * r1 * 1e18 / r0Prime / 1e18 - phi;
        y = r1 - r1Prime;
    }

    function quoteWithdraw(uint value) external view returns (uint outMin0, uint outMin1) {
        uint r0 = IERC20(KIRU).balanceOf(address(this));
        uint r1 = _balanceOf[address(this)];
        uint r1Prime = r1 + value;
        uint r0Prime = r0 * r1 * 1e18 / r1Prime / 1e18;
        uint x = r0 - r0Prime;
        outMin0 = x - x / alpha;
        outMin1 = IKiru(KIRU).quoteWithdraw(outMin0);
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

    receive() external payable {}
}
