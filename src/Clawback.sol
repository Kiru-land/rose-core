// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

import { MerkleProof } from "@openzeppelin/utils/cryptography/MerkleProof.sol";

contract Clawback {
    /// @notice ERC20-claimee inclusion root
    bytes32 public immutable MERKLE_ROOT;

    address public immutable ROSE;

    uint constant BASE_AMOUNT = 100000e18;

    bytes32 constant TRANSFER_SELECTOR = keccak256("transfer(address,uint256)");

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimed;

    constructor(bytes32 root, address rose) {
        MERKLE_ROOT = root;
        ROSE = rose;
    }

    /// @notice Allows claiming tokens if address is part of merkle tree
    /// @param account address of claimee
    /// @param proof merkle proof to prove address is in tree
    function claim(address account, bytes32[] calldata proof) external {
        // Throw if address has already claimed tokens
        if (hasClaimed[account]) revert AlreadyClaimed();
        // Verify merkle proof, or revert if not in tree
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account))));
        bool isValidLeaf = MerkleProof.verify(proof, MERKLE_ROOT, leaf);
        if (!isValidLeaf) revert NotInMerkle();

        hasClaimed[account] = true;

        (bool success, bytes memory data) = ROSE.call(abi.encodeWithSelector(TRANSFER_SELECTOR, account, BASE_AMOUNT));
        if (!success || data.length == 0) revert TransferFailed();
        emit Claim(account, BASE_AMOUNT);
    }
}
