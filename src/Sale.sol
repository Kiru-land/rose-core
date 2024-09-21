// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract OversubscribedTokenSale {

    address immutable TOKEN;
    uint256 immutable TO_SELL;
    uint256 immutable SOFT_CAP;
    uint256 immutable HARD_CAP;
    uint256 immutable SALE_END;

    uint256 public totalRaised; // slot 0
    bool saleEnded; // slot 1

    mapping(address => uint256) contributions; // slot 2
    mapping(address => bool) hasClaimed; // slot 3

    bytes32 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    event Contributed(address indexed contributor, uint256 amount);
    event Claimed(address indexed contributor, uint256 tokenAmount, uint256 refundAmount);

    constructor(address _token, uint256 _toSell, uint256 _softCap, uint256 _hardCap, uint256 _duration) {
        TOKEN = _token;
        TO_SELL = _toSell;
        SOFT_CAP = _softCap;
        HARD_CAP = _hardCap;
        SALE_END = block.timestamp + _duration;
    }

    receive() external payable {
        assembly {
            if lt(SALE_END.slot, timestamp()) { revert(0, 0) }
            if lt(msg.value, 1) { revert(0, 0) }

            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 2)
            let contribSlot := keccak256(ptr, 0x40)
            sstore(totalRaised.slot, add(sload(totalRaised.slot), callvalue()))
            sstore(contribSlot, add(sload(contribSlot), callvalue()))
        }
    }

    function endSale() external {
        assembly {
            if lt(SALE_END.slot, timestamp()) { revert(0, 0) }
            if sload(saleEnded.slot) { revert(0, 0) }
            sstore(saleEnded.slot, 1)
        }
    }

    function claim() external {
        assembly {
            let ptr := mload(0x40)
            // assert(saleEnded);
            if iszero(sload(saleEnded.slot)) { revert(0, 0) }
            // assert(contributions[msg.sender] > 0);
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 2)
            let contribSlot := keccak256(ptr, 0x40)
            if iszero(sload(contribSlot)) { revert(0, 0) }
            // assert(!hasClaimed[msg.sender]);
            mstore(add(ptr, 0x20), 3)
            let hasClaimedSlot := keccak256(ptr, 0x40)
            if sload(hasClaimedSlot) { revert(0, 0) }
            sstore(hasClaimedSlot, 1)
            /*
             * if the soft cap is not met, refund the entire allocation
             */
            if lt(totalRaised.slot, SOFT_CAP.slot) {
                let refundSuccess := call(gas(), caller(), contributionAmount, 0, 0, 0, 0)
                if iszero(refundSuccess) { revert(0, 0) }
            }
            /*
             * if the soft cap has been met, distribute the tokens proportionally to the individual contributions
             */
            if ge(totalRaised.slot, SOFT_CAP.slot) {
                /*
                 * contributionRatio = contributionAmount / totalRaised
                 * toDistribute = contributionRatio * TO_SELL
                 */
                let scaledRatio := div(mul(contributionAmount, 1000000), totalRaised)
                let amountOut := div(mul(scaledRatio, TO_SELL), 1000000)
                mstore(ptr, shl(224, _TRANSFER_SELECTOR))
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), amountOut)
                let distributeSuccess := call(gas(), TOKEN, 0, ptr, 0x44, 0, 0)
                if iszero(distributeSuccess) { revert(0, 0) }
            }
            /*
             * if the hard cap has been met, refund the excess contribution
             */
            if ge(totalRaised.slot, HARD_CAP.slot) {
                /*
                 * excess = contributionRatio * (totalRaised - HARD_CAP)
                 */
                let excess := div(mul(scaledRatio, sub(totalRaised.slot, HARD_CAP)), 1000000)
                let refundSuccess := call(gas(), caller(), excess, 0, 0, 0, 0)
                if iszero(refundSuccess) { revert(0, 0) }
            }
        }
    }
}
