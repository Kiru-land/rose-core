// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract OversubscribedTokenSale {
    IERC20 public immutable token;
    uint256 public immutable softCap;
    uint256 public immutable hardCap;
    uint256 public immutable saleEndTime;
    uint256 public totalRaised;
    bool public saleEnded;

    mapping(address => uint256) public contributions;
    mapping(address => bool) public hasClaimed;

    event Contributed(address indexed contributor, uint256 amount);
    event Claimed(address indexed contributor, uint256 tokenAmount, uint256 refundAmount);

    constructor(IERC20 _token, uint256 _softCap, uint256 _hardCap, uint256 _duration) {
        require(_softCap < _hardCap, "Soft cap must be less than hard cap");
        token = _token;
        softCap = _softCap;
        hardCap = _hardCap;
        saleEndTime = block.timestamp + _duration;
    }

    function contribute() external payable {
        require(block.timestamp < saleEndTime, "Sale has ended");
        require(msg.value > 0, "Contribution must be greater than 0");

        totalRaised += msg.value;
        contributions[msg.sender] += msg.value;

        emit Contributed(msg.sender, msg.value);
    }

    function endSale() external {
        require(block.timestamp >= saleEndTime, "Sale has not ended yet");
        require(!saleEnded, "Sale has already been ended");

        saleEnded = true;
    }

    function claim() external {
        require(saleEnded, "Sale has not ended yet");
        require(!hasClaimed[msg.sender], "Already claimed");
        require(contributions[msg.sender] > 0, "No contribution found");

        uint256 contributionAmount = contributions[msg.sender];
        uint256 tokenAmount;
        uint256 refundAmount;

        if (totalRaised < softCap) {
            // If soft cap not reached, refund entire contribution
            refundAmount = contributionAmount;
        } else if (totalRaised <= hardCap) {
            // If between soft cap and hard cap, distribute tokens proportionally
            tokenAmount = (contributionAmount * token.balanceOf(address(this))) / totalRaised;
        } else {
            // If above hard cap, distribute tokens and refund excess
            uint256 effectiveContribution = (contributionAmount * hardCap) / totalRaised;
            tokenAmount = (effectiveContribution * token.balanceOf(address(this))) / hardCap;
            refundAmount = contributionAmount - effectiveContribution;
        }

        hasClaimed[msg.sender] = true;

        if (tokenAmount > 0) {
            require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
        }
        if (refundAmount > 0) {
            payable(msg.sender).transfer(refundAmount);
        }

        emit Claimed(msg.sender, tokenAmount, refundAmount);
    }

    // Allow contract to receive ETH
    receive() external payable {
        contribute();
    }
}