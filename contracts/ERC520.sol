// SPDX-License-Identifier: MIT

/* 
    EEEEEEEEE   RRRRRRRRRR     CCCCCCCCCC          5555555555  222222222   0000000000
    EEE         RRR     RRR    CCC                 555               222   000    000
    EEE         RRR     RRR    CCC                 555               222   000    000
    EEEEEEEEE   RRRRRRRRR      CCC         ####    5555555555      222     000    000
    EEE         RRR    RRR     CCC                        555   222        000    000
    EEE         RRR     RRR    CCC                        555  222         000    000
    EEEEEEEEE   RRR      RRR   CCCCCCCCCC          5555555555  222222222   0000000000

    ERC-520 introduces Accretive Tokens, a pioneering asset class that seamlessly integrates 
    ERC-721 NFTs with ERC-20 valuation tokens. Inspired by the five classes of scarcity, 
    ERC-520 defines a unique genesis NFT structure where each class maintains a delicate 
    balance between rarity and value. The total supply is strictly limited to 2100 genesis NFTs, 
    ensuring exclusivity and long-term appreciation.

    Each Accretive Token possesses the remarkable ability to be fractionalized into fungible 
    ERC-20 tokens, enabling shared ownership and unlocking limitless possibilities for 
    liquidity and accessibility. Through a mechanism of deflection, value is strategically 
    distributed, reinforcing sustainable appreciation while maintaining equilibrium in the 
    ecosystem. Just like diamonds in the real world, Accretive Tokens represent a store of 
    value in crypto, designed to appreciate over time through structured growth.

    Coined in 2024 and developed by
    Eric Chan 
    0xab4964e3CCFB1963E5CaBB0929F53758a3f523f0
    
    Co-developed by
    Hiroshi Tatenokawa 
    0x23fB57C75BE13Cd57a2F4D42a9594110B802c3fc
    

**/

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./accretiveToken.sol";


contract ERC520 is ERC721, ReentrancyGuard {

    // Connect with ERC520.org and get featured 
    address public constant PLATFORM = 0xEc134D437173FdaE507E05c69F249a42352Efe62;
    uint256 public constant CLAIM_INTERVAL = 4147200;            // arbitrum, montly 60*60*24*30/0.625 = 4,147,200
    
    uint256 public constant INITIAL_RESERVED = 2_020_000 * 1e18; // 1_500_000 LP + 520,000 Creator incentive 
    uint256 public MAX_GENESIS_SUPPLY = 2_100;
    uint256 public MAX_TOKEN_SUPPLY = 21_000_000;

    address public Creator;
    uint256 public lastID;

    uint256 public startBlock;

    uint256 public creatorReward = 52_000;                       // 52,000 x 10
    uint256 public MAX_CLAIMS = 10;
    uint256 public lastClaimBlock;  

    address public accretiveTokenAddress;
    string[] public metadata;

    IERC20 public token;
    
    mapping(address => bool) public owners;
    mapping(address => uint256[]) public nftOwned;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint256) public _tokenIP;

    event TokenCreated(address tokenAddress);
    event liquidated(address indexed owner, uint256 indexed tokenId, uint256 liquidatedValue, uint256 blockNumber);
    event CreatorRewardClaimed(address indexed claimer, uint256 amount, uint256 blockNumber);


    modifier onlyOwner() {
        require(owners[msg.sender], "Caller is not the owner");
        _;
    }

    
    constructor(
        string memory _nftName, 
        string memory _nftTicker, 
        string memory _tokenName, 
        string memory _tokenTicker, 
        address _launchpadContract,
        string[] memory metadataURL
    ) ERC721(_nftName, string(abi.encodePacked(_nftTicker))) {

        Creator = msg.sender;
        owners[msg.sender] = true;
        owners[_launchpadContract] = true;
        startBlock = block.number;

        accretiveTokenAddress = address(new AccreativeToken(_tokenName, _tokenTicker, address(this)));
        token = IERC20(accretiveTokenAddress);

        emit TokenCreated(accretiveTokenAddress);
        //set metadata
        setMetadata(metadataURL);
    }

    function setMetadata(string[] memory metadataURL) public onlyOwner {
        uint256 length = metadataURL.length; 
        for (uint256 i = 0; i < length; i++) {
            metadata.push(metadataURL[i]);
        }
    }

    
    function addOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Not zero address");
        owners[newOwner] = true;
    }

    function removeOwner(address ownerToRemove) external onlyOwner {
        require(ownerToRemove != msg.sender, "Cannot remove yourself");
        require(owners[ownerToRemove], "Address is not an owner");
        delete owners[ownerToRemove];
    }

    function openMint(address _to) public onlyOwner returns (uint256) {
        require(MAX_GENESIS_SUPPLY >=  lastID);
  
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.timestamp,block.prevrandao,lastID))) % 100;

        uint256 index;

        // Map random number to the respective group based on probability
        if (randomNum < 5) {
            index = 0; // 0-4: 5%
        } else if (randomNum < 15) {
            index = 1; // 5-14: 10%
        } else if (randomNum < 30) {
            index = 2; // 15-29: 15%
        } else if (randomNum < 60) {
            index = 3; // 30-59: 30%
        } else {
            index = 4; // 60-99: 40%
        }

        lastID++;

        _mint(_to, lastID);
        _setTokenURI(lastID, metadata[index]);
        _setTokenIP (lastID, index);

        nftOwned[_to].push(lastID);


        return lastID;
    }
    
    function totalMetadata ()external view returns  (uint256) {
        return metadata.length;
    }


    function burn(uint256 _tokenId) external nonReentrant{

        // Ensure burn need to be after go live 


        uint256 _blocknumber = block.number;

        // Ensure the sender owns the specified NFT
        require(ownerOf(_tokenId) == msg.sender, "NFT not owned by sender");

        // Burn the NFT
        _burn(_tokenId);

        // Remove the NFT from the sender's owned list
        _removeNFTFromOwnedList(msg.sender, _tokenId);

        // this got problem 
        uint256 accreativBalance = appreciation();

        uint256 claimAmount = accreativBalance / MAX_GENESIS_SUPPLY;

        uint256 holderAllocation = claimAmount * 95 /100;

        uint256 royalty = (claimAmount - holderAllocation) / 2;


        // Holder allocation
        token.transfer(msg.sender, holderAllocation );

        // Creator royalty
        token.transfer(msg.sender, royalty);

        // Platform royalty
        token.transfer(PLATFORM, royalty);


        // Update MAX_GENESIS_SUPPLY
        require(MAX_GENESIS_SUPPLY > 0, "No supply left");
        MAX_GENESIS_SUPPLY -= 1;

        // Emit event
        emit liquidated(msg.sender, _tokenId, claimAmount, _blocknumber);
    }

    // Helper function to remove an NFT from the sender's owned list
    function _removeNFTFromOwnedList(address owner, uint256 tokenId) internal {
        uint256[] storage ownedNFTs = nftOwned[owner];
        uint256 length =ownedNFTs.length; 
        for (uint256 i = 0; i < length; i++) {
            if (ownedNFTs[i] == tokenId) {
                ownedNFTs[i] = ownedNFTs[ownedNFTs.length - 1]; // Replace with the last element
                ownedNFTs.pop(); // Remove the last element
                break;
            }
        }
    }

    function appreciation() public view returns (uint256) {
        uint256 accretiveValue = token.balanceOf(address(this)) - (MAX_CLAIMS * creatorReward * 1e18);
        return accretiveValue;
    }

    
    function claimCreatorReward() external {
        require(MAX_CLAIMS > 0, "Max claims reached");
        require(lastClaimBlock == 0 || block.number >= lastClaimBlock + CLAIM_INTERVAL, "Claim not available yet");

        uint256 rewardAmount = creatorReward * 1e18;
        token.transfer(Creator, rewardAmount);

        lastClaimBlock = block.number;
        MAX_CLAIMS -= 1; // Reduce the available claims

        // Emit event
        emit CreatorRewardClaimed(msg.sender, rewardAmount, block.number);
    }

    function totalSupply() external view returns (uint256) {
        return lastID;
    }
    

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        _tokenURIs[tokenId] = _tokenURI;
    }

    function _setTokenIP(uint256 tokenId, uint256 _IP) internal {
        _tokenIP [tokenId] = _IP;
    }


    function getTokenIP(uint256 tokenId) external view returns (uint256, string memory) {
        return (_tokenIP[tokenId], _tokenURIs[tokenId]);
    }

    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory _tokenURI = _tokenURIs[tokenId];
        return bytes(_tokenURI).length > 0 ? _tokenURI : super.tokenURI(tokenId);
    }


    function ownedNFT(address _user) public view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory ownedTokens = nftOwned[_user];
        uint256[] memory tokenIPs = new uint256[](ownedTokens.length);
        uint256 length = ownedTokens.length;
        for (uint256 i = 0; i < length; i++) {
            tokenIPs[i] = _tokenIP[ownedTokens[i]];
        }

        return (ownedTokens, tokenIPs);
    }

    function balanceOfERC520 (address _user) public view returns (uint256, uint256){
        // balance of ERC721 and ERC20
        return (balanceOf(_user), token.balanceOf(_user));
    }

    function getAllMetadata() external view returns (string[] memory) {
        return metadata;
    }

    function getERC520() external view returns (
        string memory, string memory, address, address, uint256, uint256, uint256, uint256){
        return (
            name(),
            symbol(),
            Creator, 
            accretiveTokenAddress,
            balanceOf(address(this)),
            lastID,
            MAX_CLAIMS,
            MAX_GENESIS_SUPPLY
            );
    }

    function creator() external view returns (address) {
        return Creator; // or `creator` if it's public already
    }


    /**
     * @dev Override the _transfer function to update nftOwned.
     */
    function safeTransferWithCustomLogic(
        address from,
        address to,
        uint256 tokenId
    ) public {
        safeTransferFrom(from, to, tokenId);

        // Custom logic after the base transfer
        _removeNFTFromOwner(from, tokenId);
        _addNFTToOwner(to, tokenId);
        
    }



    /**
     * @dev Remove the tokenId from the sender's nftOwned array.
     */
    function _removeNFTFromOwner(address owner, uint256 tokenId) internal {
        uint256[] storage ownedTokens = nftOwned[owner];
        uint256 length = ownedTokens.length;
        for (uint256 i = 0; i < length; i++) {
            if (ownedTokens[i] == tokenId) {
                // Replace the current token with the last token in the array
                ownedTokens[i] = ownedTokens[ownedTokens.length - 1];
                // Remove the last token
                ownedTokens.pop();
                break;
            }
        }
    }

    /**
     * @dev Add the tokenId to the receiver's nftOwned array.
     */
    function _addNFTToOwner(address owner, uint256 tokenId) internal {
        nftOwned[owner].push(tokenId);
    }


    function transferToken(address targetContract, uint256 amount) public onlyOwner {
        require(targetContract != address(0), "Invalid target contract address");
        require(amount != 0, "Amount must be greater than zero");

        // Interact with the token contract to transfer tokens
        bool success = token.transfer(targetContract, amount);
        require(success, "VT Token transfer failed");
    }
}
