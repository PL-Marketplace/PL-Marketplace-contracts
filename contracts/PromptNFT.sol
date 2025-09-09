// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PromptNFT
 * @notice ERC-721 NFT contract for AI prompt ownership
 * @dev Each NFT represents a unique AI prompt with encrypted content
 */
contract PromptNFT is ERC721, ERC721URIStorage, Ownable {
    // Token ID counter
    uint256 private _tokenIdCounter;

    // Marketplace contract address (can list/transfer NFTs)
    address public marketplace;

    // Category enum for gas efficiency
    enum Category {
        Writing,
        Coding,
        Marketing,
        Design,
        Analysis,
        Translation,
        Education,
        ImageGeneration,
        Other
    }

    // Prompt metadata
    struct PromptMetadata {
        string encryptedDataCID;    // IPFS CID of encrypted prompt
        string publicMetadataCID;   // IPFS CID of public metadata
        uint256 createdAt;
        address creator;
        Category category;          // Prompt category
    }

    // Token ID to metadata
    mapping(uint256 => PromptMetadata) public promptMetadata;

    // Creator to token IDs
    mapping(address => uint256[]) public creatorTokens;

    // Category to token IDs for efficient filtering
    mapping(Category => uint256[]) public categoryTokens;

    // Events
    event PromptMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string publicMetadataCID,
        Category category
    );
    event MarketplaceUpdated(address indexed newMarketplace);

    constructor() ERC721("Prompt License NFT", "PLNFT") Ownable(msg.sender) {
        // Start token IDs at 1
        _tokenIdCounter = 1;
    }

    /**
     * @notice Set the marketplace contract address
     * @param _marketplace The marketplace contract address
     */
    function setMarketplace(address _marketplace) external onlyOwner {
        require(_marketplace != address(0), "Invalid marketplace");
        marketplace = _marketplace;
        emit MarketplaceUpdated(_marketplace);
    }

    /**
     * @notice Mint a new prompt NFT
     * @param to The recipient address
     * @param encryptedDataCID IPFS CID of encrypted prompt content
     * @param publicMetadataCID IPFS CID of public metadata
     * @param category The category of the prompt
     * @return tokenId The minted token ID
     */
    function mintPrompt(
        address to,
        string memory encryptedDataCID,
        string memory publicMetadataCID,
        Category category
    ) external returns (uint256) {
        require(to != address(0), "Invalid recipient");
        require(bytes(encryptedDataCID).length > 0, "Missing encrypted data");
        require(bytes(publicMetadataCID).length > 0, "Missing metadata");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, publicMetadataCID);

        promptMetadata[tokenId] = PromptMetadata({
            encryptedDataCID: encryptedDataCID,
            publicMetadataCID: publicMetadataCID,
            createdAt: block.timestamp,
            creator: to,
            category: category
        });

        creatorTokens[to].push(tokenId);
        categoryTokens[category].push(tokenId);

        emit PromptMinted(tokenId, to, publicMetadataCID, category);

        return tokenId;
    }

    /**
     * @notice Get all tokens created by an address
     * @param creator The creator address
     * @return Token IDs created by this address
     */
    function getCreatorTokens(address creator) external view returns (uint256[] memory) {
        return creatorTokens[creator];
    }

    /**
     * @notice Get all token IDs for a specific category
     * @param category The category to filter by
     * @return Token IDs in this category
     */
    function getTokensByCategory(Category category) external view returns (uint256[] memory) {
        return categoryTokens[category];
    }

    /**
     * @notice Get count of tokens in a category
     * @param category The category to count
     * @return Number of tokens in this category
     */
    function getCategoryTokenCount(Category category) external view returns (uint256) {
        return categoryTokens[category].length;
    }

    /**
     * @notice Check if caller is approved or owner
     * @param tokenId The token to check
     * @return True if caller can transfer this token
     */
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool) {
        return _isAuthorized(ownerOf(tokenId), spender, tokenId);
    }

    /**
     * @notice Override to check marketplace approval
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow marketplace to transfer without explicit approval
        if (msg.sender != marketplace) {
            require(
                from == address(0) || _isAuthorized(from, auth, tokenId),
                "Unauthorized"
            );
        }

        return super._update(to, tokenId, auth);
    }

    // Required overrides
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
