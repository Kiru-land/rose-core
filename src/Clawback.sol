// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26; 

import { MerkleProof } from "@openzeppelin/utils/cryptography/MerkleProof.sol";

contract Clawback {
    /// @notice ERC20-claimee inclusion root
    bytes32 public immutable MERKLE_ROOT;

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimed;

    constructor(bytes32 root) {
        MERKLE_ROOT = root;
    }

    /// @notice Allows claiming tokens if address is part of merkle tree
    /// @param to address of claimee
    /// @param amount of tokens owed to claimee
    /// @param proof merkle proof to prove address and amount are in tree
    function claim(address to, uint256 amount, bytes32[] calldata proof) external {
        // Throw if address has already claimed tokens
        if (hasClaimed[to]) revert AlreadyClaimed();
        // Verify merkle proof, or revert if not in tree
        bytes32 leaf = keccak256(abi.encodePacked(to, amount));
        bool isValidLeaf = MerkleProof.verify(proof, MERKLE_ROOT, leaf);
        if (!isValidLeaf) revert NotInMerkle();

        hasClaimed[to] = true;

        _mint(to, amount);
        emit Claim(to, amount);
    }
}
