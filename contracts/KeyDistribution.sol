// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title KeyDistribution
 * @notice Manages key distribution and disputes for encrypted prompts
 * @dev Integrates with Hedera Consensus Service for key distribution
 */
contract KeyDistribution is Ownable {
    
    // HCS Topic for key distribution
    string public hcsTopicId;
    
    // Key commitment structure
    struct KeyCommitment {
        bytes32 commitment;
        uint256 timestamp;
        bool revealed;
        uint256 revealDeadline;
    }
    
    // Dispute structure
    struct Dispute {
        address buyer;
        uint256 tokenId;
        uint256 timestamp;
        bool resolved;
        bool refunded;
    }
    
    // Mappings
    mapping(uint256 => KeyCommitment) public keyCommitments;
    mapping(uint256 => Dispute[]) public tokenDisputes;
    mapping(address => uint256) public pendingRefunds;
    
    // Constants
    uint256 public constant REVEAL_DEADLINE = 24 hours;
    uint256 public constant DISPUTE_PERIOD = 7 days;
    
    // Events
    event HCSTopicSet(string topicId);
    event KeyCommitted(uint256 indexed tokenId, bytes32 commitment, uint256 deadline);
    event KeyRevealed(uint256 indexed tokenId);
    event DisputeRaised(uint256 indexed tokenId, address indexed buyer);
    event DisputeResolved(uint256 indexed tokenId, uint256 disputeIndex, bool refunded);
    event RefundIssued(address indexed buyer, uint256 amount);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Set HCS topic ID for key distribution
     * @param _topicId Hedera Consensus Service topic ID
     */
    function setHCSTopic(string memory _topicId) external onlyOwner {
        require(bytes(_topicId).length > 0, "Invalid topic ID");
        hcsTopicId = _topicId;
        emit HCSTopicSet(_topicId);
    }
    
    /**
     * @notice Commit to a key for a token
     * @param tokenId The NFT token ID
     * @param commitment Hash of the encryption key
     */
    function commitKey(uint256 tokenId, bytes32 commitment) external {
        require(commitment != bytes32(0), "Invalid commitment");
        require(keyCommitments[tokenId].commitment == bytes32(0), "Already committed");
        
        uint256 deadline = block.timestamp + REVEAL_DEADLINE;
        
        keyCommitments[tokenId] = KeyCommitment({
            commitment: commitment,
            timestamp: block.timestamp,
            revealed: false,
            revealDeadline: deadline
        });
        
        emit KeyCommitted(tokenId, commitment, deadline);
    }
    
    /**
     * @notice Reveal a key (must match commitment)
     * @param tokenId The NFT token ID
     * @param key The actual encryption key
     */
    function revealKey(uint256 tokenId, string memory key) external {
        KeyCommitment storage commitment = keyCommitments[tokenId];
        require(commitment.commitment != bytes32(0), "No commitment");
        require(!commitment.revealed, "Already revealed");
        
        // Verify key matches commitment
        bytes32 keyHash = keccak256(abi.encodePacked(key));
        require(keyHash == commitment.commitment, "Key mismatch");
        
        commitment.revealed = true;
        
        // Emit event for off-chain HCS submission
        emit KeyRevealed(tokenId);
    }
    
    /**
     * @notice Raise a dispute for missing key
     * @param tokenId The NFT token ID
     */
    function raiseDispute(uint256 tokenId) external {
        KeyCommitment memory commitment = keyCommitments[tokenId];
        require(commitment.commitment != bytes32(0), "No commitment");
        require(!commitment.revealed, "Key already revealed");
        require(block.timestamp > commitment.revealDeadline, "Deadline not passed");
        
        tokenDisputes[tokenId].push(Dispute({
            buyer: msg.sender,
            tokenId: tokenId,
            timestamp: block.timestamp,
            resolved: false,
            refunded: false
        }));
        
        emit DisputeRaised(tokenId, msg.sender);
    }
    
    /**
     * @notice Resolve a dispute (owner only)
     * @param tokenId The NFT token ID
     * @param disputeIndex Index in the disputes array
     * @param refundAmount Amount to refund (0 for no refund)
     */
    function resolveDispute(
        uint256 tokenId,
        uint256 disputeIndex,
        uint256 refundAmount
    ) external onlyOwner {
        require(disputeIndex < tokenDisputes[tokenId].length, "Invalid dispute");
        
        Dispute storage dispute = tokenDisputes[tokenId][disputeIndex];
        require(!dispute.resolved, "Already resolved");
        
        dispute.resolved = true;
        
        if (refundAmount > 0) {
            dispute.refunded = true;
            pendingRefunds[dispute.buyer] += refundAmount;
        }
        
        emit DisputeResolved(tokenId, disputeIndex, refundAmount > 0);
    }
    
    /**
     * @notice Claim pending refunds
     */
    function claimRefund() external {
        uint256 amount = pendingRefunds[msg.sender];
        require(amount > 0, "No refund");
        
        pendingRefunds[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Refund failed");
        
        emit RefundIssued(msg.sender, amount);
    }
    
    /**
     * @notice Check if key is revealed for a token
     * @param tokenId The NFT token ID
     * @return revealed Whether the key has been revealed
     */
    function isKeyRevealed(uint256 tokenId) external view returns (bool) {
        return keyCommitments[tokenId].revealed;
    }
    
    /**
     * @notice Get disputes for a token
     * @param tokenId The NFT token ID
     * @return disputes Array of disputes
     */
    function getTokenDisputes(uint256 tokenId) external view returns (Dispute[] memory) {
        return tokenDisputes[tokenId];
    }
    
    /**
     * @notice Receive HBAR for refunds
     */
    receive() external payable {}
}
