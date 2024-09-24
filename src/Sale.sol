// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
// TODO: a way to collect the ETH to TOKEN.TREASURY(), or a way to permisionlessly add liquidity to the pool and keep some
// TODO a way to keep some funds in the contract in case of refunds

import "./Rose.sol";

contract PublicSale {

    address public immutable TREASURY;
    address public immutable OWNER;
    uint256 public immutable SOFT_CAP;
    uint256 public immutable HARD_CAP;
    uint256 public immutable SALE_END;
    uint256 public immutable LIQ_RATIO;

    uint256 public totalRaised; // slot 0
    bool public saleEnded; // slot 1
    address public token; // slot 2
    uint256 public toSell; // slot 3

    mapping(address => uint256) contributions; // slot 4
    mapping(address => bool) hasClaimed; // slot 5



    bytes32 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    constructor(uint256 _softCap, uint256 _hardCap, uint256 _duration, uint256 liqRatio, address _treasury) {
        SOFT_CAP = _softCap;
        HARD_CAP = _hardCap;
        SALE_END = block.timestamp + _duration;
        LIQ_RATIO = liqRatio;
        TREASURY = _treasury;
        OWNER = msg.sender;
    }

    receive() external payable {
        uint _SALE_END = SALE_END;
        assembly {
            if lt(_SALE_END, timestamp()) { revert(0, 0) }
            if lt(callvalue(), 1) { revert(0, 0) }

            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 4)
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
        uint _TO_SELL = toSell;
        address _TOKEN = token;
        bytes32 _TRANSFER_SELECTOR = TRANSFER_SELECTOR;
        assembly {
            let ptr := mload(0x40)
            // assert(saleEnded);
            if iszero(sload(saleEnded.slot)) { revert(0, 0) }
            // assert(contributions[msg.sender] > 0);
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), 4)
            let contribSlot := keccak256(ptr, 0x40)
            let contributionAmount := sload(contribSlot)
            if iszero(contributionAmount) { revert(0, 0) }
            // assert(!hasClaimed[msg.sender]);
            mstore(add(ptr, 0x20), 5)
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
                let scalingFactor := 1000000000000000000 // 10^18    
                let scaledRatio := div(mul(contributionAmount, scalingFactor), totalRaisedValue)
                let amountOut := div(mul(scaledRatio, _TO_SELL), scalingFactor)
                mstore(ptr, _TRANSFER_SELECTOR)
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
                    let excess := div(mul(scaledRatio, sub(totalRaisedValue, _HARD_CAP)), scalingFactor)
                    let refundSuccess := call(gas(), caller(), excess, 0, 0, 0, 0)
                    if iszero(refundSuccess) { revert(0, 0) }
                }
            }
        }
    }

    function wrapUp() external {
        uint256 _HARD_CAP = HARD_CAP;
        uint256 _LIQ_RATIO = LIQ_RATIO;
        uint256 _SOFT_CAP = SOFT_CAP;
        address _TOKEN = token;
        
        assembly {
            log1(0, 0, 1)
            // Check if sale has ended
            if iszero(sload(saleEnded.slot)) { revert(0, 0) }
            log1(0, 0, 2)
            // Check if the token contract has been deployed
            if iszero(_TOKEN) { revert(0, 0) }
            log1(0, 0, 3)
            let totalRaisedValue := sload(totalRaised.slot)
            
            // Revert if totalRaised < SOFT_CAP
            if lt(totalRaisedValue, _SOFT_CAP) { revert(0, 0) }
            log1(0, 0, 4)
            // Calculate the amount to send to TOKEN contract
            let liqAmount
            let treasuryAmount
            if lt(totalRaisedValue, _HARD_CAP) {
                log1(0, 0, 5)
                // If SOFT_CAP < totalRaised < HARD_CAP
                liqAmount := div(mul(totalRaisedValue, _LIQ_RATIO), 1000000)
                treasuryAmount := sub(totalRaisedValue, liqAmount)
            }
            if iszero(lt(totalRaisedValue, _HARD_CAP)) {
                log1(0, 0, 6)
                // If totalRaised >= HARD_CAP
                liqAmount := div(mul(_HARD_CAP, _LIQ_RATIO), 1000000)
                treasuryAmount := sub(_HARD_CAP, liqAmount)
            }

            // Send funds to TOKEN contract
            let success1 := call(gas(), _TOKEN, liqAmount, 0, 0, 0, 0)
            if iszero(success1) { revert(0, 0) }
            log1(0, 0, 7)
            // Get TREASURY address from TOKEN contract
            let ptr := mload(0x40)
            mstore(ptr, 0x3e5e3c23000000000000000000000000000000000000000000000000000000) // TREASURY() selector
            let success2 := staticcall(gas(), _TOKEN, ptr, 4, ptr, 0x20)
            log1(0, 0, 8)
            if iszero(success2) { revert(0, 0) }
            let treasuryAddress := mload(ptr)
            log1(0, 0, 9)
            // Send remaining funds to TREASURY
            let success3 := call(gas(), treasuryAddress, treasuryAmount, 0, 0, 0, 0)
            if iszero(success3) { revert(0, 0) }
            log1(0, 0, 10)
        }
    }

    function deploy(uint _alpha, uint _phi, uint256 _supply, uint256 _r1InitRatio, uint256 _forSaleRatio) external payable returns (address) {
        require(msg.sender == OWNER, "Only owner can deploy");
        require(address(token) == address(0), "Token already deployed");
        token = address(new Rose{value: msg.value}(_alpha, _phi, TREASURY, _supply, _r1InitRatio, _forSaleRatio));
        toSell = Rose(payable(token)).balanceOf(address(this));
        return token;
    }
}