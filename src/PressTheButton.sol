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

    address private constant MULTISIG = 0x2d69b5b0C06f5C0b14d11D9bc7e622AC5316c018;

    function press() external payable {
        assert(msg.value >= 0.001 ether && msg.value <= 1 ether);
        if (!_checkDuration()) { return; }
        pressooor = msg.sender;
        speed = msg.value;
        pressTime = block.timestamp;
        totalPresses++;
        bucket += msg.value - (msg.value / 50);
    }

    function checkDuration() public view returns (bool) {
        return _checkDuration();
    }

    function _checkDuration() private view returns (bool) {
        return block.timestamp < pressTime + _getDuration();
    }

    function getDuration() public view returns (uint256) {
        return _getDuration();
    }

    function _getDuration() internal view returns (uint256) {
        uint256 logMin = log2(0.01 ether);
        uint256 logMax = log2(1 ether);
        uint256 logSpeed = log2(speed);

        uint256 scale = (logSpeed - logMin) * 1e8 / (logMax - logMin);
        uint256 time = 3600 - (3600 - 60) * scale / 1e8;

        return time;
    }

    function log2(uint256 x) internal pure returns (uint256) {
        require(x > 0, "Input must be greater than 0");
        uint256 result = 0;

        if (x >= 2**128) {
            x >>= 128;
            result += 128;
        }
        if (x >= 2**64) {
            x >>= 64;
            result += 64;
        }
        if (x >= 2**32) {
            x >>= 32;
            result += 32;
        }
        if (x >= 2**16) {
            x >>= 16;
            result += 16;
        }
        if (x >= 2**8) {
            x >>= 8;
            result += 8;
        }
        if (x >= 2**4) {
            x >>= 4;
            result += 4;
        }
        if (x >= 2**2) {
            x >>= 2;
            result += 2;
        }
        if (x >= 2**1) {
            result += 1;
        }

        return result;
    }

    function startWindow() public payable {
        require(msg.sender == MULTISIG,"Only multisig can start the window");
        speed = 0.01 ether;
        require(!_checkDuration(),"Window already open");
        bucket = msg.value;
        pressTime = block.timestamp;
    }

    function collectBucket() public {
        require(!_checkDuration(),"Window is still open");
        (bool success,) = payable(pressooor).call{value: bucket}("");
        require(success,"Failed to send ETH to pressooor");
        bucket = 0;
    }

    function collectFees(uint amount) public {
        require(msg.sender == MULTISIG,"Only multisig can collect");
        if (!_checkDuration()) {
            require(amount <= address(this).balance - bucket,"amount exceeds available fees");
        }
        (bool success,) = payable(MULTISIG).call{value: amount}("");
        require(success,"Failed to send ETH to multisig");
        bucket = 0;
    }

    receive() external payable {}
}
