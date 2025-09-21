// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./PromptNFT.sol";

/**
 * @title EscrowMarketplace (HBAR-only)
 * @notice Escrow-based marketplace for encrypted prompt sales on Hedera EVM.
 *
 * Key points:
 * - HBAR only (no USDC at all)
 * - All prices & msg.value are WEI-HBAR (1e18), like ETH.
 * - timeoutSecs is a DURATION (seconds), min 1h, max 30d.
 * - Delivery proof is bound to a specific escrow via: hKeyCommit = keccak256(abi.encodePacked(escrowId, hKeyBase))
 * - Platform fee only (no creator fee).
 * - On-chain active listings index for simple pagination.
 */
contract EscrowMarketplace is ReentrancyGuard, Pausable, AccessControl {
    // -------- Roles --------
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");

    // -------- External --------
    PromptNFT public immutable promptNFT;

    // -------- Platform settings --------
    uint256 public platformFeeBps = 250;           // 2.5% (basis points)
    address public platformTreasury;
    
    // -------- Data --------
    struct Listing {
        address seller;
        uint256 price;     // WEI-HBAR (1e18)
        bytes32 cid;       // ciphertext CID (digest32 stored on-chain)
        bytes32 hPrompt;   // commitment: H(prompt || sP)
        bytes32 hKeyBase;  // commitment base: H(K || sK) used for escrow-specific binding
        bool active;
    }

    struct Escrow {
        uint256 tokenId;
        address buyer;
        address seller;
        uint256 amount;      // WEI-HBAR (exact listing price)
        uint64  timeout;     // unix seconds
        bytes32 cid;
        bytes32 hKeyBase;
        bool delivered;
        bool refunded;
    }

    mapping(uint256 => Listing) public listings; // tokenId => listing
    mapping(uint256 => Escrow)  public escrows;  // escrowId => escrow
    uint256 public escrowCounter = 1;            // start at 1 (not 0)

    // Platform HBAR earnings (from fees)
    uint256 public platformHBARBalance;

    // Active listing index for pagination (tokenIds)
    uint256[] private activeTokenIds;
    mapping(uint256 => uint256) private activeIndexOf; // tokenId => 1-based index in activeTokenIds

    // -------- Events --------
    event Listed(
        uint256 indexed tokenId,
        address indexed seller,
        bytes32 cid,
        bytes32 hPrompt,
        bytes32 hKeyBase,
        uint256 price
    );

    event Unlisted(uint256 indexed tokenId);

    event EscrowOpened(
        uint256 indexed escrowId,
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 amount,
        uint64 timeout,
        bytes   buyerEncryptPubKey
    );

    event KeyDelivered(
        uint256 indexed escrowId,
        bytes32 hKeyCommit,
        bytes32 topicId,
        uint64 consensusSecs,
        uint32 sequence
    );

    event Refunded(uint256 indexed escrowId, uint256 amount);

    event PlatformFeeUpdated(uint256 newFeeBps);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event PlatformWithdrawal(address indexed treasury, uint256 hbarAmount);

    // -------- Modifiers --------
    modifier onlyOracle() {
        require(hasRole(ORACLE_ROLE, msg.sender), "Not oracle");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    // -------- Ctor --------
    constructor(address _promptNFT, address _treasury, address _admin) {
        require(_promptNFT != address(0), "Invalid NFT");
        require(_treasury != address(0), "Invalid treasury");
        require(_admin != address(0), "Invalid admin");

        promptNFT = PromptNFT(_promptNFT);
        platformTreasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // -------- Listing --------
    function listPrompt(
        uint256 tokenId,
        bytes32 cid,
        bytes32 hPrompt,
        bytes32 hKeyBase,
        uint256 price
    ) external {
        require(promptNFT.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!listings[tokenId].active, "Already listed");
        require(cid != bytes32(0), "Invalid CID");
        require(hPrompt != bytes32(0), "Invalid hPrompt");
        require(hKeyBase != bytes32(0), "Invalid hKeyBase");
        require(price > 0, "Invalid price");

        listings[tokenId] = Listing({
            seller:   msg.sender,
            price:    price,
            cid:      cid,
            hPrompt:  hPrompt,
            hKeyBase: hKeyBase,
            active:   true
        });

        _addActive(tokenId);
        emit Listed(tokenId, msg.sender, cid, hPrompt, hKeyBase, price);
    }

    function updateListingPrice(uint256 tokenId, uint256 newPrice) external {
        Listing storage L = listings[tokenId];
        require(L.seller == msg.sender, "Not seller");
        require(L.active, "Not listed");
        require(newPrice > 0, "Invalid price");
        L.price = newPrice;
    }

    function unlistPrompt(uint256 tokenId) external {
        Listing storage L = listings[tokenId];
        require(L.seller == msg.sender, "Not seller");
        require(L.active, "Not listed");
        L.active = false;
        _removeActive(tokenId);
        emit Unlisted(tokenId);
    }

    // -------- Purchase / Escrow --------

    /**
     * @notice Purchase with escrow (HBAR-only).
     * @param tokenId            NFT tokenId being sold
     * @param buyerEncryptPubKey Buyer's 32-byte encryption pubkey (e.g., X25519)
     * @param timeoutSecs        Delivery timeout duration (seconds) [3600..2592000]
     */
    function purchaseWithEscrow(
        uint256 tokenId,
        bytes calldata buyerEncryptPubKey,
        uint64 timeoutSecs
    ) external payable nonReentrant whenNotPaused returns (uint256 escrowId) {
        Listing memory L = listings[tokenId];
        require(L.active, "Not listed");
        require(L.seller != msg.sender, "Cannot buy own");
        require(buyerEncryptPubKey.length == 32, "Pubkey must be 32 bytes");
        require(timeoutSecs >= 3600 && timeoutSecs <= 2592000, "Invalid timeout"); // 1h..30d

        // Require full payment (fees are separate; they do NOT reduce msg.value)
        require(msg.value >= L.price, "Insufficient HBAR");

        // Refund any overpayment (no dust left)
        uint256 refund = msg.value - L.price;
        if (refund > 0) {
            (bool refunded, ) = msg.sender.call{value: refund}("");
            require(refunded, "Refund failed");
        }

        // Always credit the listing price
        uint256 escrowAmount = L.price;

        escrowId = escrowCounter++;
        uint64 timeout = uint64(block.timestamp) + timeoutSecs;

        escrows[escrowId] = Escrow({
            tokenId:   tokenId,
            buyer:     msg.sender,
            seller:    L.seller,
            amount:    escrowAmount,
            timeout:   timeout,
            cid:       L.cid,
            hKeyBase:  L.hKeyBase,
            delivered: false,
            refunded:  false
        });

        emit EscrowOpened(escrowId, tokenId, msg.sender, escrowAmount, timeout, buyerEncryptPubKey);
    }

    /**
     * @notice Oracle confirms key delivery (releases funds)
     * @param escrowId     Target escrow
     * @param hKeyCommit   keccak256(abi.encodePacked(escrowId, hKeyBase)) computed off-chain by relayer after HCS proof
     * @param topicId      HCS topicId
     * @param consensusSecs HCS consensus timestamp
     * @param sequence     HCS sequence number
     */
    function confirmKeyDelivery(
        uint256 escrowId,
        bytes32 hKeyCommit,
        bytes32 topicId,
        uint64 consensusSecs,
        uint32 sequence
    ) external onlyOracle nonReentrant {
        Escrow storage E = escrows[escrowId];
        require(E.buyer != address(0), "Invalid escrow");
        require(!E.delivered, "Already delivered");
        require(!E.refunded, "Already refunded");
        require(topicId != bytes32(0), "Invalid topic");
        require(consensusSecs > 0, "Invalid timestamp");

        // Bind commitment to this escrow id
        bytes32 expected = keccak256(abi.encodePacked(escrowId, E.hKeyBase));
        require(hKeyCommit == expected, "Key commit mismatch");

        // CEI: mark delivered before transfers
        E.delivered = true;

        // Fees
        uint256 fee = (E.amount * platformFeeBps) / 10_000;
        uint256 sellerNet = E.amount - fee;

        platformHBARBalance += fee;

        (bool sellerPaid, ) = E.seller.call{value: sellerNet}("");
        require(sellerPaid, "Seller payment failed");

        emit KeyDelivered(escrowId, hKeyCommit, topicId, consensusSecs, sequence);
    }

    /**
     * @notice Buyer can claim refund after timeout if not delivered
     */
    function claimRefund(uint256 escrowId) external nonReentrant {
        Escrow storage E = escrows[escrowId];
        require(msg.sender == E.buyer, "Not buyer");
        require(!E.delivered, "Already delivered");
        require(!E.refunded, "Already refunded");
        require(block.timestamp >= E.timeout, "Not timed out");

        E.refunded = true;

        (bool ok, ) = E.buyer.call{value: E.amount}("");
        require(ok, "Refund failed");

        emit Refunded(escrowId, E.amount);
    }

    // -------- Admin --------
    function withdrawPlatformEarnings() external onlyAdmin nonReentrant {
        uint256 hbarAmount = platformHBARBalance;
        require(hbarAmount > 0, "No earnings");
        platformHBARBalance = 0;

        (bool sent, ) = platformTreasury.call{value: hbarAmount}("");
        require(sent, "HBAR transfer failed");

        emit PlatformWithdrawal(platformTreasury, hbarAmount);
    }

    function updatePlatformFee(uint256 newFeeBps) external onlyAdmin {
        require(newFeeBps <= 1000, "Fee too high"); // <=10%
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(newFeeBps);
    }

    function updateTreasury(address newTreasury) external onlyAdmin {
        require(newTreasury != address(0), "Invalid treasury");
        address old = platformTreasury;
        platformTreasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    function pause() external onlyAdmin { _pause(); }
    function unpause() external onlyAdmin { _unpause(); }

    // -------- Views --------
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    function getListing(uint256 tokenId) external view returns (Listing memory) {
        return listings[tokenId];
    }

    function canRefund(uint256 escrowId) external view returns (bool) {
        Escrow memory E = escrows[escrowId];
        return !E.delivered && !E.refunded && block.timestamp >= E.timeout;
    }

    function getActiveCount() external view returns (uint256) {
        return activeTokenIds.length;
    }

    function getActiveSlice(uint256 offset, uint256 limit) external view returns (uint256[] memory) {
        uint256 n = activeTokenIds.length;
        if (offset >= n) return new uint256[](0);
        uint256 end = offset + limit; if (end > n) end = n;
        uint256 m = end - offset;
        uint256[] memory out = new uint256[](m);
        for (uint256 i; i < m; i++) out[i] = activeTokenIds[offset + i];
        return out;
    }

    // -------- Internals --------
    function _addActive(uint256 tokenId) internal {
        if (activeIndexOf[tokenId] != 0) return; // already active
        activeTokenIds.push(tokenId);
        activeIndexOf[tokenId] = activeTokenIds.length; // store 1-based index
    }

    function _removeActive(uint256 tokenId) internal {
        uint256 idx1 = activeIndexOf[tokenId];
        if (idx1 == 0) return;
        uint256 idx0 = idx1 - 1;
        uint256 last = activeTokenIds.length - 1;

        if (idx0 != last) {
            uint256 moved = activeTokenIds[last];
            activeTokenIds[idx0] = moved;
            activeIndexOf[moved] = idx1;
        }
        activeTokenIds.pop();
        activeIndexOf[tokenId] = 0;
    }

    // -------- Receive/Fallback --------
    receive() external payable {}
    fallback() external payable {}
}
