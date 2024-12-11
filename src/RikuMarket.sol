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
    function transferFrom(address, address, uint) external;
    function balanceOf(address) external view returns (uint);
}

/**
  * @title Riku Market - Evil Kiru
  *
  *     -----      ------      ------
  * -> | ETH | -> | Kiru | -> | Riku | ->
  *     -----      ------      ------
  *
  *     ------      ------      -----
  * <- | Riku | <- | Kiru | <- | ETH | <-
  *     ------      ------      -----
  */
contract RikuMarket {

    //////////////////////////////////////////////////////////////
    /////////////////////////// State ////////////////////////////
    //////////////////////////////////////////////////////////////

    /*
     * @notice The parameter alpha
     *         Alpha is the global parameter that controls the amount
     *         of tokens burned per unit of Kiru deposited/withdrawn.
     */
    uint alpha;

    address public constant KIRU = 0xe04d4E49Fd4BCBcE2784cca8B80CFb35A4C01da2;
    address public treasury = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;
    address public riku;

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

    constructor(uint _alpha) {
        alpha = _alpha;
    }

    //////////////////////////////////////////////////////////////
    ///////////////////////// Initialize /////////////////////////
    //////////////////////////////////////////////////////////////

    function init(address _riku) external {
        require(msg.sender == treasury, "only treasury can initialize");
        riku = _riku;
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Deposit ///////////////////////////
    //////////////////////////////////////////////////////////////

    function deposit(uint outMin0, uint outMin1) external payable {
        uint r0 = IERC20(KIRU).balanceOf(address(this));
        /*
         * Deposit into Kiru
         */
        IKiru(KIRU).deposit{value: msg.value}(outMin0);
        /*
         * Swap Kiru to Riku
         */
        uint kiruBalanceAfter = IERC20(KIRU).balanceOf(address(this));
        uint x = kiruBalanceAfter - r0;
        uint r1 = IERC20(riku).balanceOf(address(this));
        uint r0Prime = r0 + x;
        uint r1Prime = r0 * r1 * 1e18 / r0Prime / 1e18;
        uint y = r1 - r1Prime;
        uint phi = y / alpha;
        y -= phi;
        require(y >= outMin1, "slippage bounds reached");
        IERC20(riku).transfer(msg.sender, y);
        IERC20(riku).transfer(address(0), phi);
        emit Deposit(msg.sender, x, y);
    }

    //////////////////////////////////////////////////////////////
    ////////////////////////// Withdraw //////////////////////////
    //////////////////////////////////////////////////////////////

    /**
      * @notice Withdraws Riku to ETH
      *
      * @dev Caller must approve Riku before calling this function
      */
    function withdraw(uint y, uint outMin0, uint outMin1) external {
        uint r0 = IERC20(KIRU).balanceOf(address(this));
        uint r1 = IERC20(riku).balanceOf(address(this));
        uint r1Prime = r1 + y;
        uint r0Prime = r0 * r1 * 1e18 / r1Prime / 1e18;
        uint x = r0 - r0Prime;
        uint phi = x / alpha;
        x -= phi;
        require(x >= outMin0, "slippage bounds reached");
        IERC20(riku).transferFrom(msg.sender, address(this), y);
        IERC20(KIRU).transfer(address(0), phi);
        /**
          * Withdraw from Kiru
          */
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
        uint r1 = IERC20(riku).balanceOf(address(this));
        uint r0Prime = r0 + x;
        uint r1Prime = r0 * r1 * 1e18 / r0Prime / 1e18;
        y = r1 - r1Prime;
        y -= y / alpha;
    }

    function quoteWithdraw(uint value) external view returns (uint outMin0, uint outMin1) {
        uint r0 = IERC20(KIRU).balanceOf(address(this));
        uint r1 = IERC20(riku).balanceOf(address(this));
        uint r1Prime = r1 + value;
        uint r0Prime = r0 * r1 * 1e18 / r1Prime / 1e18;
        uint x = r0 - r0Prime;
        outMin0 = x - x / alpha;
        outMin1 = IKiru(KIRU).quoteWithdraw(outMin0);
    }

    receive() external payable {}
}
