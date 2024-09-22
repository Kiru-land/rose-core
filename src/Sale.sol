// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract PublicSale {

    address public immutable TOKEN;
    uint256 public immutable TO_SELL;
    uint256 public immutable SOFT_CAP;
    uint256 public immutable HARD_CAP;
    uint256 public immutable SALE_END;

    uint256 public totalRaised; // slot 0
    bool public saleEnded; // slot 1

    mapping(address => uint256) contributions; // slot 2
    mapping(address => bool) hasClaimed; // slot 3

    bytes32 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    constructor(address _token, uint256 _toSell, uint256 _softCap, uint256 _hardCap, uint256 _duration) {
        TOKEN = _token;
        TO_SELL = _toSell;
        SOFT_CAP = _softCap;
        HARD_CAP = _hardCap;
        SALE_END = block.timestamp + _duration;
    }

    receive() external payable {
        uint _SALE_END = SALE_END;
        assembly {
            if lt(_SALE_END, timestamp()) { revert(0, 0) }
            if lt(callvalue(), 1) { revert(0, 0) }

            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 2)
            let contribSlot := keccak256(ptr, 0x40)
            sstore(totalRaised.slot, add(sload(totalRaised.slot), callvalue()))
            sstore(contribSlot, add(sload(contribSlot), callvalue()))
        }
    }

    function endSale() external {
        uint _SALE_END = SALE_END;
        assembly {
            if lt(_SALE_END, timestamp()) { revert(0, 0) }
            if sload(saleEnded.slot) { revert(0, 0) }
            sstore(saleEnded.slot, 1)
        }
    }

    function claim() external {
        uint _SOFT_CAP = SOFT_CAP;
        uint _HARD_CAP = HARD_CAP;
        uint _TO_SELL = TO_SELL;
        address _TOKEN = TOKEN;
        bytes32 _TRANSFER_SELECTOR = TRANSFER_SELECTOR;
        assembly {
            let ptr := mload(0x40)
            // assert(saleEnded);
            if iszero(sload(saleEnded.slot)) { revert(0, 0) }
            // assert(contributions[msg.sender] > 0);
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 2)
            let contribSlot := keccak256(ptr, 0x40)
            let contributionAmount := sload(contribSlot)
            if iszero(contributionAmount) { revert(0, 0) }
            // assert(!hasClaimed[msg.sender]);
            mstore(add(ptr, 0x20), 3)
            let hasClaimedSlot := keccak256(ptr, 0x40)
            if sload(hasClaimedSlot) { revert(0, 0) }
            sstore(hasClaimedSlot, 1)
            let totalRaisedValue := sload(totalRaised.slot)
            /*
             * if the soft cap is not met, refund the entire allocation
             */
            if lt(totalRaisedValue, _SOFT_CAP) {
                let refundSuccess := call(gas(), caller(), contributionAmount, 0, 0, 0, 0)
                if iszero(refundSuccess) { revert(0, 0) }
            }
            /*
             * if the soft cap has been met, distribute the tokens proportionally to the individual contributions
             */
            if iszero(lt(totalRaisedValue, _SOFT_CAP)) {
                /*
                 * contributionRatio = contributionAmount / totalRaised
                 * toDistribute = contributionRatio * TO_SELL
                 */
                let scaledRatio := div(mul(contributionAmount, 1000000), totalRaisedValue)
                let amountOut := div(mul(scaledRatio, _TO_SELL), 1000000)
                mstore(ptr, shl(224, _TRANSFER_SELECTOR))
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), amountOut)
                // Send tokens to the caller
                let distributeSuccess := call(gas(), _TOKEN, 0, ptr, 0x44, 0, 0)
                if iszero(distributeSuccess) { revert(0, 0) }
                /*
                * if the hard cap has been met, refund the excess contribution
                */
                if iszero(lt(totalRaisedValue, _HARD_CAP)) {
                    /*
                    * excess = contributionRatio * (totalRaised - HARD_CAP)
                    */
                    let excess := div(mul(scaledRatio, sub(totalRaisedValue, _HARD_CAP)), 1000000)
                    let refundSuccess := call(gas(), caller(), excess, 0, 0, 0, 0)
                    if iszero(refundSuccess) { revert(0, 0) }
                }
            }
        }
    }
}
