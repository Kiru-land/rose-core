// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Rose.sol";
import { MerkleProof } from "@openzeppelin/utils/cryptography/MerkleProof.sol";

contract PublicSale {

    /// @notice Address where a portion of the raised funds will be sent
    address public immutable TREASURY;
    /// @notice Minimum amount of funds to be raised for the sale to be considered successful
    uint256 public immutable SOFT_CAP;
    /// @notice Maximum amount of funds that can be raised in the sale
    uint256 public immutable HARD_CAP;
    /// @notice Timestamp when the sale will end
    uint256 public immutable SALE_END;
    /// @notice Percentage of raised funds for liquidity (in basis points)
    uint256 public immutable LIQ_RATIO;

    // ***** Deploy parameters *****
    /// @notice R0_INIT is the initial reserve of ROSE R₁(0)
    uint256 public constant R0_INIT = 1 ether;
    /// @notice ALPHA_INIT is the initial skew factor
    uint256 public constant ALPHA = 10_000;
    /// @notice PHI_FACTOR is the slash factor
    uint256 public constant PHI = 1_000;
    /// @notice R1_INIT is the initial reserve of ROSE R₁(0)
    uint256 public constant R1_INIT = 200_000_000 * 1e18;   
    /// @notice FOR_SALE is the amount of tokens to be sold in the sale
    uint256 public constant FOR_SALE = 620_000_000 * 1e18;
    /// @notice TREASURY_ALLOCATION is the amount of tokens to be allocated to the treasury
    uint256 public constant TREASURY_ALLOCATION = 80_000_000 * 1e18;
    /// @notice CLAWBACK is the amount of tokens to be allocated to communities
    uint256 public constant CLAWBACK = 100_000_000 * 1e18;
    /// @notice ERC20-claimee inclusion root
    bytes32 public immutable MERKLE_ROOT;
    // @notice the number of claimees
    uint256 public immutable CLAIMEES;

    // Total amount of funds raised in the sale
    uint256 public totalRaised; // slot 0
    // Flag to indicate if the sale has ended
    bool public saleEnded; // slot 1
    // Address of the token contract
    address public token; // slot 2
    // Amount of tokens to be sold in the sale
    uint256 public toSell; // slot 3

    // Mapping to track individual contributions
    mapping(address => uint256) contributions; // slot 4
    // Mapping to track if an address has claimed their tokens
    mapping(address => bool) hasClaimed; // slot 5

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimedClawback;

    // selector for the balanceOf function
    bytes32 constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));
    // Selector for the transfer function
    bytes32 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    event ClawbackClaimed(address to);

    /**
     * @dev Constructor to initialize the sale parameters
     * @param _softCap Minimum amount to raise
     * @param _hardCap Maximum amount to raise
     * @param _duration Duration of the sale in seconds
     * @param liqRatio Percentage of raised funds for liquidity (in basis points)
     * @param _treasury Address of the treasury
     */
    constructor(
        uint256 _softCap, 
        uint256 _hardCap, 
        uint256 _duration, 
        uint256 liqRatio, 
        address _treasury,
        bytes32 _merkleRoot, 
        uint256 _claimees
    ) {
        SOFT_CAP = _softCap;
        HARD_CAP = _hardCap;
        SALE_END = block.timestamp + _duration;
        LIQ_RATIO = liqRatio;
        TREASURY = _treasury;
        MERKLE_ROOT = _merkleRoot;
        CLAIMEES = _claimees;
    }

    /**
     * @dev Fallback function to receive contributions
     * Allows users to send ETH directly to the contract
     */
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

    /**
     * @dev Function to end the sale
     * Can only be called after the sale end time
     */
    function endSale() external {
        uint _SALE_END = SALE_END;
        assembly {
            if lt(timestamp(), _SALE_END) { revert(0, 0) }
            if sload(saleEnded.slot) { revert(0, 0) }
            sstore(saleEnded.slot, 1)
        }
    }

    /**
     * @dev Function for users to claim their tokens or refunds
     * Distributes tokens if soft cap is met, otherwise refunds contributions
     */
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

    /**
     * @dev Internalunction to finalize the sale and distribute funds
     * Sends funds to the token contract for liquidity and to the treasury
     */
    function _wrapUp() internal {
        uint256 _HARD_CAP = HARD_CAP;
        uint256 _LIQ_RATIO = LIQ_RATIO;
        uint256 _SOFT_CAP = SOFT_CAP;
        address _TOKEN = token;
        
        assembly {
            // Check if sale has ended
            if iszero(sload(saleEnded.slot)) { revert(0, 0) }
            // Check if the token contract has been deployed
            if iszero(_TOKEN) { revert(0, 0) }
            let totalRaisedValue := sload(totalRaised.slot)
            
            // Revert if totalRaised < SOFT_CAP
            if lt(totalRaisedValue, _SOFT_CAP) { revert(0, 0) }
            // Calculate the amount to send to TOKEN contract
            let liqAmount
            let treasuryAmount
            
            if lt(totalRaisedValue, _HARD_CAP) {
                // If SOFT_CAP < totalRaised < HARD_CAP
                liqAmount := div(mul(totalRaisedValue, _LIQ_RATIO), 1000000)
                treasuryAmount := sub(totalRaisedValue, liqAmount)
            }
            if iszero(lt(totalRaisedValue, _HARD_CAP)) {
                // If totalRaised >= HARD_CAP
                liqAmount := div(mul(_HARD_CAP, _LIQ_RATIO), 1000000)
                treasuryAmount := sub(_HARD_CAP, liqAmount)
            }

            // Send funds to TOKEN contract
            let success1 := call(gas(), _TOKEN, liqAmount, 0, 0, 0, 0)
            if iszero(success1) { revert(0, 0) }
            // Get TREASURY address from TOKEN contract
            let ptr := mload(0x40)
            mstore(ptr, shl(224, 0x2d2c5565)) // TREASURY() selector
            let success2 := staticcall(gas(), _TOKEN, ptr, 4, ptr, 0x20)
            if iszero(success2) { revert(0, 0) }
            let treasuryAddress := mload(ptr)
            // Send remaining funds to TREASURY
            let success3 := call(gas(), treasuryAddress, treasuryAmount, 0, 0, 0, 0)
            if iszero(success3) { revert(0, 0) }
        }
    }

    /**
     * @dev Function to deploy the token contract
     */
    function deploy() external payable returns (address) {
        require(totalRaised >= SOFT_CAP, "Soft cap not met");
        require(token == address(0), "Token already deployed");
        require(saleEnded, "Sale must end before deploying token");
        require(msg.value >= R0_INIT, "Insufficient Ether for deployment");
        token = address(new Rose{value: R0_INIT}(
            ALPHA, 
            PHI, 
            R1_INIT, 
            FOR_SALE, 
            TREASURY_ALLOCATION, 
            CLAWBACK,
            TREASURY
        ));
        toSell = Rose(payable(token)).balanceOf(address(this)) - CLAWBACK;
        _wrapUp();
        return token;
    }

    /// @notice Allows claiming tokens if address is part of merkle tree
    /// @param to address of claimee
    /// @param proof merkle proof to prove address is in the tree
    function claimClawback(address to, bytes32[] calldata proof) external {
        // Throw if address has already claimed tokens
        require(token != address(0), "Token not deployed");
        require(!hasClaimedClawback[to], "Already claimed");
        
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(to))));
        bool isValidLeaf = MerkleProof.verify(proof, MERKLE_ROOT, leaf);
        require(isValidLeaf, "Not in merkle");

        hasClaimedClawback[to] = true;

        Rose rose = Rose(payable(token));

        uint256 baseAmount = (CLAWBACK * 1e6) / CLAIMEES / 1e6;
        (bool balanceSuccess, bytes memory balanceData) = address(rose).call(abi.encodeWithSignature("balanceOf(address)", address(this)));
        require(balanceSuccess && balanceData.length == 32, "Balance call failed");
        uint256 clawbackBalance = abi.decode(balanceData, (uint256));
        require(clawbackBalance >= baseAmount, "Insufficient clawback balance");
        (bool transferSuccess, bytes memory transferData) = address(rose).call(abi.encodeWithSignature("transfer(address,uint256)", to, baseAmount));
        require(transferSuccess && transferData.length == 0, "Transfer failed");
        emit ClawbackClaimed(to);
    }
}
