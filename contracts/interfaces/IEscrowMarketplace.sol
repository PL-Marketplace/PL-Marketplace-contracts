// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IEscrowMarketplace
 * @notice Interface for the escrow-based prompt marketplace
 */
interface IEscrowMarketplace {
    struct Listing {
        address seller;
        uint256 price;
        uint16 feeBps;
        bytes32 cid;        // keccak256 of raw CID or multihash digest
        bytes32 hPrompt;    // H(prompt || sP) — sP only revealed inside decrypted payload
        bytes32 hKeyBase;   // H(K || sK)
        bool active;
        bool acceptsHBAR;
        bool acceptsUSDC;
    }

    struct Escrow {
        uint256 tokenId;
        address buyer;
        address seller;
        uint256 amount;
        uint64 timeout;     // unix seconds
        bool isUSDC;
        bytes32 cid;
        bytes32 hKeyBase;
        bool delivered;
        bool refunded;
    }

    // Events
    event Listed(
        uint256 indexed tokenId, 
        address indexed seller,
        bytes32 cid, 
        bytes32 hPrompt, 
        bytes32 hKeyBase, 
        uint256 price, 
        uint16 feeBps,
        bool acceptsHBAR,
        bool acceptsUSDC
    );
    
    event EscrowOpened(
        uint256 indexed escrowId, 
        uint256 indexed tokenId, 
        address indexed buyer,
        uint256 amount,
        bool isUSDC, 
        uint64 timeout, 
        bytes buyerEncryptPubKey
    );
    
    event KeyDelivered(
        uint256 indexed escrowId, 
        bytes32 hKeyBase, 
        bytes32 topicId, 
        uint64 consensusSecs, 
        uint32 sequence
    );
    
    event Refunded(uint256 indexed escrowId, uint256 amount, bool isUSDC);

    // Main functions
    function listPrompt(
        uint256 tokenId,
        bytes32 cid,
        bytes32 hPrompt,
        bytes32 hKeyBase,
        uint256 price,
        uint16 feeBps,
        bool acceptsHBAR,
        bool acceptsUSDC
    ) external;

    function purchaseWithEscrow(
        uint256 tokenId,
        bool useUSDC,
        bytes calldata buyerEncryptPubKey,
        uint64 timeoutSecs
    ) external payable returns (uint256 escrowId);

    // Oracle-only function
    function confirmKeyDelivery(
        uint256 escrowId,
        bytes32 hKeyBase,
        bytes32 topicId,
        uint64 consensusSecs,
        uint32 sequence
    ) external;

    // Buyer function
    function claimRefund(uint256 escrowId) external;

    // View functions
    function getListing(uint256 tokenId) external view returns (Listing memory);
    function getEscrow(uint256 escrowId) external view returns (Escrow memory);
    function canRefund(uint256 escrowId) external view returns (bool);
}