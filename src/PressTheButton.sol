// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
  * @title PressTheButton 🔘
  *
  * @author Kiru
  */
contract PressTheButton {

    /// @notice Total number of button presses
    uint256 public totalPresses;

    /// @notice Total ETH collected in the bucket
    uint256 public bucket;

    /// @notice Address of the last pressooor
    address public pressooor;

    /// @notice Current count speed
    uint256 public speed;

    /// @notice Timestamp of the last press
    uint256 public pressTime;

    uint256 private constant BASE_DURATION = 30 seconds;

    address private constant MULTISIG = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    function press() external payable {
        assert(msg.value >= 0.001 ether && msg.value <= 1 ether);
        if (!checkDuration()) { return; }
        pressooor = msg.sender;
        speed = msg.value;
        pressTime = block.timestamp;
        totalPresses++;
        bucket += msg.value - (msg.value / 50);
    }

    function checkDuration() private view returns (bool) {
        return block.timestamp < pressTime + getDuration();
    }

    function getDuration() private view returns (uint256) {
        uint256 numerator = (speed - 1e15) * (1e18 - 1e17);
        uint256 denominator = 1e18 - 1e15;
        uint256 y = 1e17 + (numerator / denominator);
        return BASE_DURATION * 1e18 / y;
    }

    function startWindow() public payable {
        require(msg.sender == MULTISIG,"Only multisig can start the window");
        require(!checkDuration(),"Window already open");
        speed = 0.001 ether;
        pressTime = block.timestamp;
    }

    function collectBucket() public {
        require(!checkDuration(),"Window is still open");
        (bool success,) = payable(pressooor).call{value: bucket}("");
        require(success,"Failed to send ETH to pressooor");
        bucket = 0;
    }

    function collectFees(uint amount) public {
        require(msg.sender == MULTISIG,"Only multisig can collect");
        if (!checkDuration()) {
            require(amount <= address(this).balance - bucket,"amount exceeds available fees");
        }
        (bool success,) = payable(MULTISIG).call{value: amount}("");
        require(success,"Failed to send ETH to multisig");
        bucket = 0;
    }

    receive() external payable {}
}
