// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PromptNFT
 * @notice ERC-721 NFT contract for AI prompt ownership
 * @dev Each NFT represents a unique AI prompt with encrypted content
 */
contract PromptNFT is ERC721, ERC721URIStorage, AccessControl {
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Token ID counter
    uint256 private _tokenIdCounter;

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
        address creator;            // Original creator (for royalties)
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
        string encryptedDataCID,
        string publicMetadataCID,
        Category category
    );

    constructor(address _admin) ERC721("Prompt License NFT", "PLNFT") {
        require(_admin != address(0), "Invalid admin");
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        // Start token IDs at 0
        _tokenIdCounter = 0;
    }

    /**
     * @notice Create a new prompt NFT
     * @param metadata The prompt metadata including CIDs
     * @param category The category of the prompt
     * @return tokenId The minted token ID
     */
    function createPrompt(
        PromptMetadata memory metadata,
        Category category
    ) external returns (uint256) {
        require(hasRole(MINTER_ROLE, msg.sender) || msg.sender == tx.origin, "Not authorized");
        require(bytes(metadata.encryptedDataCID).length > 0, "Missing encrypted data");
        require(bytes(metadata.publicMetadataCID).length > 0, "Missing metadata");

        uint256 tokenId = _tokenIdCounter++;
        
        // Mint to the caller
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadata.publicMetadataCID);

        // Store metadata with creator as msg.sender
        promptMetadata[tokenId] = PromptMetadata({
            encryptedDataCID: metadata.encryptedDataCID,
            publicMetadataCID: metadata.publicMetadataCID,
            createdAt: block.timestamp,
            creator: msg.sender, // Original creator for royalties
            category: category
        });

        // Update mappings
        creatorTokens[msg.sender].push(tokenId);
        categoryTokens[category].push(tokenId);

        emit PromptMinted(
            tokenId, 
            msg.sender, 
            metadata.encryptedDataCID,
            metadata.publicMetadataCID, 
            category
        );

        return tokenId;
    }

    /**
     * @notice Get the original creator of a token (for royalties)
     * @param tokenId The token ID
     * @return creator The original creator address
     */
    function getCreator(uint256 tokenId) external view returns (address) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return promptMetadata[tokenId].creator;
    }

    /**
     * @notice Grant marketplace role to an address
     * @param marketplace The marketplace contract address
     */
    function grantMarketplaceRole(address marketplace) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MARKETPLACE_ROLE, marketplace);
    }

    /**
     * @notice Get tokens created by a specific address
     * @param creator The creator address
     * @return Token IDs created by this address
     */
    function getCreatorTokens(address creator) external view returns (uint256[] memory) {
        return creatorTokens[creator];
    }

    /**
     * @notice Get tokens in a specific category
     * @param category The category to filter by
     * @return Token IDs in this category
     */
    function getCategoryTokens(Category category) external view returns (uint256[] memory) {
        return categoryTokens[category];
    }

    /**
     * @notice Get paginated tokens by category
     * @param category The category to filter by
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return tokenIds Array of token IDs
     */
    function getCategoryTokensPaginated(
        Category category,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory tokenIds) {
        uint256[] storage tokens = categoryTokens[category];
        uint256 total = tokens.length;
        
        if (offset >= total) {
            return new uint256[](0);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        tokenIds = new uint256[](end - offset);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = tokens[offset + i];
        }
    }

    /**
     * @notice Get total supply of tokens
     * @return The total number of tokens minted
     */
    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Override to allow marketplace to transfer without approval
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Allow marketplace to transfer without approval
        if (hasRole(MARKETPLACE_ROLE, msg.sender)) {
            return super._update(to, tokenId, auth);
        }
        
        // Standard ERC721 authorization check
        if (from != address(0)) {
            require(
                from == msg.sender || 
                isApprovedForAll(from, msg.sender) || 
                getApproved(tokenId) == msg.sender,
                "Not authorized"
            );
        }
        
        return super._update(to, tokenId, auth);
    }

    // Required overrides for multiple inheritance
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
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}