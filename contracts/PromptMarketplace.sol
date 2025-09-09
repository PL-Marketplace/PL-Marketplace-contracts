// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./PromptNFT.sol";

/**
 * @title PromptMarketplace
 * @notice Marketplace for buying and selling prompt NFT licenses
 * @dev Handles payments, royalties, and license distribution
 */
contract PromptMarketplace is ReentrancyGuard, Pausable, Ownable {
    
    // NFT contract
    PromptNFT public promptNFT;
    
    // Payment tokens
    address public immutable usdcToken;
    
    // Platform settings
    uint256 public platformFeeBps = 250; // 2.5%
    address public platformTreasury;
    
    // Import Category enum from PromptNFT
    PromptNFT.Category public constant Writing = PromptNFT.Category.Writing;
    PromptNFT.Category public constant Coding = PromptNFT.Category.Coding;
    PromptNFT.Category public constant Marketing = PromptNFT.Category.Marketing;
    PromptNFT.Category public constant Design = PromptNFT.Category.Design;
    PromptNFT.Category public constant Analysis = PromptNFT.Category.Analysis;
    PromptNFT.Category public constant Translation = PromptNFT.Category.Translation;
    PromptNFT.Category public constant Education = PromptNFT.Category.Education;
    PromptNFT.Category public constant ImageGeneration = PromptNFT.Category.ImageGeneration;
    PromptNFT.Category public constant Other = PromptNFT.Category.Other;
    
    // Listing structure
    struct Listing {
        uint256 tokenId;
        address seller;
        uint256 priceHBAR;
        uint256 priceUSDC;
        uint32 maxLicenses;      // 0 = unlimited
        uint32 soldLicenses;
        bool isActive;
        uint256 createdAt;
        PromptNFT.Category category;  // Category from NFT
    }
    
    // License structure
    struct License {
        uint256 tokenId;
        uint256 purchasePrice;
        uint256 purchaseTime;
        bool paidInUSDC;
    }
    
    // State mappings
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(uint256 => License)) public userLicenses;
    mapping(uint256 => address[]) public tokenLicensees;
    mapping(address => uint256[]) public userLicensedTokens;
    
    // Category filtering
    mapping(PromptNFT.Category => uint256[]) public activeListingsByCategory;
    uint256[] public allActiveListings;
    
    // Revenue tracking
    mapping(address => uint256) public creatorEarningsUSDC;
    mapping(address => uint256) public platformEarningsUSDC;
    
    // Events
    event Listed(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 priceHBAR,
        uint256 priceUSDC,
        uint32 maxLicenses,
        PromptNFT.Category category
    );
    
    event Unlisted(uint256 indexed tokenId);
    
    event LicensePurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 price,
        bool paidInUSDC
    );
    
    event EarningsWithdrawn(
        address indexed recipient,
        uint256 amount
    );
    
    event PlatformFeeUpdated(uint256 newFeeBps);
    
    constructor(
        address _promptNFT,
        address _usdcToken,
        address _treasury
    ) Ownable(msg.sender) {
        require(_promptNFT != address(0), "Invalid NFT address");
        require(_usdcToken != address(0), "Invalid USDC address");
        require(_treasury != address(0), "Invalid treasury");
        
        promptNFT = PromptNFT(_promptNFT);
        usdcToken = _usdcToken;
        platformTreasury = _treasury;
    }
    
    /**
     * @notice Create a listing for a prompt NFT
     * @param tokenId The NFT token ID
     * @param priceHBAR Price in HBAR (tinybars)
     * @param priceUSDC Price in USDC (6 decimals)
     * @param maxLicenses Maximum licenses (0 = unlimited)
     */
    function createListing(
        uint256 tokenId,
        uint256 priceHBAR,
        uint256 priceUSDC,
        uint32 maxLicenses
    ) external {
        require(promptNFT.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(priceHBAR > 0 || priceUSDC > 0, "Must set a price");
        require(!listings[tokenId].isActive, "Already listed");
        
        // Get prompt metadata including category from NFT contract
        (,,, address creator, PromptNFT.Category category) = promptNFT.promptMetadata(tokenId);
        require(creator != address(0), "Invalid token");
        
        listings[tokenId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            priceHBAR: priceHBAR,
            priceUSDC: priceUSDC,
            maxLicenses: maxLicenses,
            soldLicenses: 0,
            isActive: true,
            createdAt: block.timestamp,
            category: category
        });
        
        // Add to active listings
        allActiveListings.push(tokenId);
        activeListingsByCategory[category].push(tokenId);
        
        emit Listed(tokenId, msg.sender, priceHBAR, priceUSDC, maxLicenses, category);
    }
    
    /**
     * @notice Remove a listing
     * @param tokenId The NFT token ID
     */
    function removeListing(uint256 tokenId) external {
        Listing storage listing = listings[tokenId];
        require(listing.seller == msg.sender, "Not seller");
        require(listing.isActive, "Not listed");
        
        listing.isActive = false;
        
        // Remove from active listings arrays
        _removeFromActiveListings(tokenId, listing.category);
        
        emit Unlisted(tokenId);
    }
    
    /**
     * @notice Purchase a license for a prompt
     * @param tokenId The NFT token ID
     * @param payInUSDC True to pay in USDC, false for HBAR
     */
    function purchaseLicense(
        uint256 tokenId,
        bool payInUSDC
    ) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[tokenId];
        require(listing.isActive, "Not listed");
        require(userLicenses[msg.sender][tokenId].purchaseTime == 0, "Already licensed");
        require(
            listing.maxLicenses == 0 || listing.soldLicenses < listing.maxLicenses,
            "No licenses available"
        );
        
        uint256 price;
        
        if (payInUSDC) {
            require(listing.priceUSDC > 0, "USDC payment not accepted");
            price = listing.priceUSDC;
            
            // Transfer USDC from buyer
            require(
                IERC20(usdcToken).transferFrom(msg.sender, address(this), price),
                "USDC transfer failed"
            );
            
            // Calculate fees
            uint256 platformFee = (price * platformFeeBps) / 10000;
            uint256 creatorAmount = price - platformFee;
            
            // Track earnings
            creatorEarningsUSDC[listing.seller] += creatorAmount;
            platformEarningsUSDC[platformTreasury] += platformFee;
            
        } else {
            require(listing.priceHBAR > 0, "HBAR payment not accepted");
            require(msg.value >= listing.priceHBAR, "Insufficient HBAR");
            price = listing.priceHBAR;
            
            // Calculate fees
            uint256 platformFee = (price * platformFeeBps) / 10000;
            uint256 creatorAmount = price - platformFee;
            
            // Transfer HBAR immediately
            (bool creatorSuccess, ) = listing.seller.call{value: creatorAmount}("");
            require(creatorSuccess, "Creator transfer failed");
            
            (bool platformSuccess, ) = platformTreasury.call{value: platformFee}("");
            require(platformSuccess, "Platform transfer failed");
            
            // Refund excess
            if (msg.value > price) {
                (bool refundSuccess, ) = msg.sender.call{value: msg.value - price}("");
                require(refundSuccess, "Refund failed");
            }
        }
        
        // Create license
        userLicenses[msg.sender][tokenId] = License({
            tokenId: tokenId,
            purchasePrice: price,
            purchaseTime: block.timestamp,
            paidInUSDC: payInUSDC
        });
        
        // Update records
        listing.soldLicenses++;
        tokenLicensees[tokenId].push(msg.sender);
        userLicensedTokens[msg.sender].push(tokenId);
        
        // Check if sold out and remove from active listings
        if (listing.maxLicenses > 0 && listing.soldLicenses >= listing.maxLicenses) {
            listing.isActive = false;
            _removeFromActiveListings(tokenId, listing.category);
        }
        
        emit LicensePurchased(tokenId, msg.sender, price, payInUSDC);
    }
    
    /**
     * @notice Get active listings by category
     * @param category The category to filter by
     * @return Array of token IDs with active listings in this category
     */
    function getActiveListingsByCategory(PromptNFT.Category category) external view returns (uint256[] memory) {
        return activeListingsByCategory[category];
    }
    
    /**
     * @notice Get all active listings
     * @return Array of all token IDs with active listings
     */
    function getAllActiveListings() external view returns (uint256[] memory) {
        return allActiveListings;
    }
    
    /**
     * @notice Get paginated active listings
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return tokenIds Array of token IDs
     */
    function getActiveListingsPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory tokenIds) {
        uint256 totalActive = allActiveListings.length;
        if (offset >= totalActive) {
            return new uint256[](0);
        }
        
        uint256 end = offset + limit;
        if (end > totalActive) {
            end = totalActive;
        }
        
        tokenIds = new uint256[](end - offset);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = allActiveListings[offset + i];
        }
    }
    
    /**
     * @notice Get paginated active listings by category
     * @param category The category to filter by
     * @param offset Starting index
     * @param limit Maximum number of results
     * @return tokenIds Array of token IDs
     */
    function getActiveListingsByCategoryPaginated(
        PromptNFT.Category category,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory tokenIds) {
        uint256[] storage categoryListings = activeListingsByCategory[category];
        uint256 total = categoryListings.length;
        
        if (offset >= total) {
            return new uint256[](0);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        tokenIds = new uint256[](end - offset);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = categoryListings[offset + i];
        }
    }
    
    /**
     * @notice Get count of active listings by category
     * @param category The category to count
     * @return Number of active listings in this category
     */
    function getActiveListingsCountByCategory(PromptNFT.Category category) external view returns (uint256) {
        return activeListingsByCategory[category].length;
    }
    
    /**
     * @notice Get total count of all active listings
     * @return Total number of active listings
     */
    function getTotalActiveListingsCount() external view returns (uint256) {
        return allActiveListings.length;
    }
    
    /**
     * @notice Internal function to remove from active listings
     */
    function _removeFromActiveListings(uint256 tokenId, PromptNFT.Category category) private {
        // Remove from allActiveListings
        uint256 length = allActiveListings.length;
        for (uint256 i = 0; i < length; i++) {
            if (allActiveListings[i] == tokenId) {
                allActiveListings[i] = allActiveListings[length - 1];
                allActiveListings.pop();
                break;
            }
        }
        
        // Remove from category array
        uint256[] storage categoryArray = activeListingsByCategory[category];
        length = categoryArray.length;
        for (uint256 i = 0; i < length; i++) {
            if (categoryArray[i] == tokenId) {
                categoryArray[i] = categoryArray[length - 1];
                categoryArray.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Withdraw USDC earnings
     */
    function withdrawEarnings() external nonReentrant {
        uint256 earnings = creatorEarningsUSDC[msg.sender];
        require(earnings > 0, "No earnings");
        
        creatorEarningsUSDC[msg.sender] = 0;
        
        require(
            IERC20(usdcToken).transfer(msg.sender, earnings),
            "Transfer failed"
        );
        
        emit EarningsWithdrawn(msg.sender, earnings);
    }
    
    /**
     * @notice Withdraw platform USDC earnings
     */
    function withdrawPlatformEarnings() external nonReentrant {
        require(msg.sender == platformTreasury, "Not treasury");
        
        uint256 earnings = platformEarningsUSDC[platformTreasury];
        require(earnings > 0, "No earnings");
        
        platformEarningsUSDC[platformTreasury] = 0;
        
        require(
            IERC20(usdcToken).transfer(platformTreasury, earnings),
            "Transfer failed"
        );
        
        emit EarningsWithdrawn(platformTreasury, earnings);
    }
    
    /**
     * @notice Check if user has license for a token
     * @param user The user address
     * @param tokenId The token ID
     * @return hasLicense Whether user has a license
     */
    function hasLicense(address user, uint256 tokenId) external view returns (bool) {
        return userLicenses[user][tokenId].purchaseTime > 0;
    }
    
    /**
     * @notice Get all licenses for a user
     * @param user The user address
     * @return tokenIds Array of licensed token IDs
     */
    function getUserLicenses(address user) external view returns (uint256[] memory) {
        return userLicensedTokens[user];
    }
    
    /**
     * @notice Get all licensees for a token
     * @param tokenId The token ID
     * @return licensees Array of licensee addresses
     */
    function getTokenLicensees(uint256 tokenId) external view returns (address[] memory) {
        return tokenLicensees[tokenId];
    }
    
    /**
     * @notice Update platform fee (owner only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "Fee too high"); // Max 10%
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(newFeeBps);
    }
    
    /**
     * @notice Pause marketplace (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause marketplace
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
