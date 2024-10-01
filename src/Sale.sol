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
    /// @notice Percentage of raised funds for liquidity (in basis points)
    uint256 public immutable LIQ_RATIO;

    // ***** Deploy parameters *****
    /// @notice R0_INIT is the initial reserve of ROSE R₁(0)
    uint256 public constant R0_INIT = 1 ether;
    /// @notice ALPHA_INIT is the initial skew factor
    uint256 public constant ALPHA = 10_000;
    /// @notice PHI_FACTOR is the slash factor
    uint256 public constant PHI = 1_000;
    /// @notice SUPPLY is the total supply of ROSE
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;
    /// @notice R1_INIT is the initial reserve of ROSE R₁(0)
    uint256 public constant R1_INIT = 200_000_000 * 1e18;   
    /// @notice FOR_SALE is the amount of tokens to be sold in the sale
    uint256 public constant SALE_ALLOCATION = 670_000_000 * 1e18;
    /// @notice TREASURY_ALLOCATION is the amount of tokens to be allocated to the treasury
    uint256 public constant TREASURY_ALLOCATION = 80_000_000 * 1e18;

    /// @notice Total amount of funds raised in the sale
    uint256 public totalRaised; // slot 0
    /// @notice Flag to indicate if the sale has ended
    bool public saleEnded; // slot 1
    /// @notice Address of the token contract
    address public token; // slot 2
    /// @notice Amount of tokens to be sold in the sale
    uint256 public saleEnd; // slot 3

    /// @notice Mapping to track individual contributions
    mapping(address => uint256) contributions; // slot 4
    /// @notice Mapping to track if an address has claimed their tokens
    mapping(address => bool) hasClaimed; // slot 5

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimedClawback;

    /// @notice Address of the owner
    address public immutable OWNER;
    /// @notice ERC20-claimee inclusion root
    bytes32 public merkleRoot;
    /// @notice base allocation for clawback
    uint256 public clawbackAllocation;

    /// @notice Selector for the transfer function, used in assembly
    bytes32 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    /// @notice Event emitted when a clawback is claimed
    event ClawbackClaimed(address to);

    /**
     * @dev Constructor to initialize the sale parameters
     * @param _softCap Minimum amount to raise
     * @param _hardCap Maximum amount to raise
     * @param _saleEnd Timestamp of sale end
     * @param liqRatio Percentage of raised funds for liquidity (in basis points)
     * @param _treasury Address of the treasury
     */
    constructor(
        uint256 _softCap, 
        uint256 _hardCap, 
        uint256 _saleEnd, 
        uint256 liqRatio, 
        address _treasury
    ) {
        SOFT_CAP = _softCap;
        HARD_CAP = _hardCap;
        saleEnd = _saleEnd;
        LIQ_RATIO = liqRatio;
        TREASURY = _treasury;
    }

    /**
     * @dev Fallback function to receive contributions
     * Allows users to send ETH directly to the contract
     */
    receive() external payable {
        uint _saleEnd = saleEnd;
        assembly {
            if lt(_saleEnd, timestamp()) { revert(0, 0) }
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
        uint _saleEnd = saleEnd;
        assembly {
            if lt(timestamp(), _saleEnd) { revert(0, 0) }
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
        uint _SALE_ALLOCATION = SALE_ALLOCATION;
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
                let amountOut := div(mul(scaledRatio, _SALE_ALLOCATION), scalingFactor)
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
     * @dev Internal function to finalize the sale and distribute funds
     * Sends funds to the token contract for liquidity and to the treasury
     */
    function _wrapUp() internal {
        uint256 _HARD_CAP = HARD_CAP;
        uint256 _LIQ_RATIO = LIQ_RATIO;
        uint256 _SOFT_CAP = SOFT_CAP;
        address _TREASURY = TREASURY;
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
            let transferLiquiditySuccess := call(gas(), _TOKEN, liqAmount, 0, 0, 0, 0)
            if iszero(transferLiquiditySuccess) { revert(0, 0) }
            // Send remaining funds to TREASURY
            let transferTreasurySuccess := call(gas(), _TREASURY, treasuryAmount, 0, 0, 0, 0)
            if iszero(transferTreasurySuccess) { revert(0, 0) }
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
            SUPPLY,
            TREASURY
        ));
        Rose rose = Rose(payable(token));
        rose.transfer(TREASURY, TREASURY_ALLOCATION);
        _wrapUp();
        return token;
    }

    /// @notice Allows claiming tokens if address is part of merkle tree
    /// @param to address of claimee
    /// @param proof merkle proof to prove address is in the tree
    function claimClawback(address to, bytes32[] calldata proof) external {
        require(block.timestamp > saleEnd, "Sale must end before claiming clawback");
        require(merkleRoot != bytes32(0), "Merkle root not set");
        // Throw if address has already claimed tokens
        require(token != address(0), "Token not deployed");
        require(!hasClaimedClawback[to], "Already claimed");
        
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(to))));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        require(isValidLeaf, "Not in merkle");

        hasClaimedClawback[to] = true;

        Rose rose = Rose(payable(token));

        uint256 tokenBalance = rose.balanceOf(address(this));
        require(tokenBalance >= clawbackAllocation, "Insufficient balance");
        rose.transfer(to, clawbackAllocation);
        emit ClawbackClaimed(to);
    }

    /// @notice Sets the merkle root and base allocation
    /// @param _merkleRoot Merkle root of the clawback merkle tree
    /// @param _clawbackAllocation Base allocation for clawback
    function setMerkleRootAndBaseAllocation(bytes32 _merkleRoot, uint256 _clawbackAllocation) external {
        require(msg.sender == OWNER, "Only owner can set merkle root");
        merkleRoot = _merkleRoot;
        clawbackAllocation = _clawbackAllocation;
    }

    /// @notice Sets the sale end timestamp and the sale ended flag
    /// @param _saleEnd Timestamp of sale end
    function setSaleEnd(uint256 _saleEnd) external {
        require(msg.sender == OWNER, "Only owner can set sale end");
        saleEnd = _saleEnd;
    }

    /// @notice Transfers the remaining allocation to the treasury
    function transferUnusedAllocation() external {
        require(msg.sender == OWNER, "Only owner can transfer unused allocation");
        require(saleEnd + 30 days < block.timestamp, "30 days must pass before transferring unused allocation");
        require(token != address(0), "Token not deployed");
        Rose rose = Rose(payable(token));
        rose.transfer(TREASURY, rose.balanceOf(address(this)));
    }

}