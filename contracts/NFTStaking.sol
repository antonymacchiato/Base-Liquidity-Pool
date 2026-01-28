// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTStaking is Ownable, ReentrancyGuard {
    struct NFTStake {
        uint256 tokenId;
        address staker;
        uint256 stakeTime;
        uint256 stakingDuration;
        bool isStaked;
        uint256 rewardMultiplier;
    }
    
    struct NFTCollection {
        address nftContract;
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        uint256 rewardMultiplier;
        bool enabled;
    }
    
    mapping(address => NFTCollection) public nftCollections;
    mapping(address => mapping(uint256 => NFTStake)) public stakedNFTs;
    mapping(address => uint256[]) public userStakedNFTs;
    
    uint256 public constant MAX_MULTIPLIER = 10000; // 100x
    uint256 public constant MIN_MULTIPLIER = 1000; // 10x
    
    event NFTStaked(address indexed staker, address indexed nftContract, uint256 tokenId, uint256 duration, uint256 multiplier);
    event NFTUnstaked(address indexed staker, address indexed nftContract, uint256 tokenId, uint256 reward);
    event CollectionAdded(address indexed nftContract, uint256 minStake, uint256 maxStake, uint256 multiplier);
    event CollectionUpdated(address indexed nftContract, uint256 minStake, uint256 maxStake, uint256 multiplier);
    
    function addNFTCollection(
        address nftContract,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 rewardMultiplier
    ) external onlyOwner {
        require(nftContract != address(0), "Invalid NFT contract");
        require(minStakeAmount <= maxStakeAmount, "Invalid stake amounts");
        require(rewardMultiplier <= MAX_MULTIPLIER, "Multiplier too high");
        require(rewardMultiplier >= MIN_MULTIPLIER, "Multiplier too low");
        
        nftCollections[nftContract] = NFTCollection({
            nftContract: nftContract,
            minStakeAmount: minStakeAmount,
            maxStakeAmount: maxStakeAmount,
            rewardMultiplier: rewardMultiplier,
            enabled: true
        });
        
        emit CollectionAdded(nftContract, minStakeAmount, maxStakeAmount, rewardMultiplier);
    }
    
    function updateNFTCollection(
        address nftContract,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 rewardMultiplier
    ) external onlyOwner {
        require(nftCollections[nftContract].nftContract != address(0), "Collection not found");
        require(minStakeAmount <= maxStakeAmount, "Invalid stake amounts");
        require(rewardMultiplier <= MAX_MULTIPLIER, "Multiplier too high");
        require(rewardMultiplier >= MIN_MULTIPLIER, "Multiplier too low");
        
        nftCollections[nftContract] = NFTCollection({
            nftContract: nftContract,
            minStakeAmount: minStakeAmount,
            maxStakeAmount: maxStakeAmount,
            rewardMultiplier: rewardMultiplier,
            enabled: true
        });
        
        emit CollectionUpdated(nftContract, minStakeAmount, maxStakeAmount, rewardMultiplier);
    }
    
    function stakeNFT(
        address nftContract,
        uint256 tokenId,
        uint256 duration
    ) external nonReentrant {
        require(nftCollections[nftContract].enabled, "Collection not enabled");
        require(nftCollections[nftContract].nftContract != address(0), "Invalid collection");
        require(ERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner");
        
        // Проверка на существующий стейкинг
        require(!stakedNFTs[nftContract][tokenId].isStaked, "NFT already staked");
        
        // Передача NFT
        ERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        
        // Создание записи о стейкинге
        stakedNFTs[nftContract][tokenId] = NFTStake({
            tokenId: tokenId,
            staker: msg.sender,
            stakeTime: block.timestamp,
            stakingDuration: duration,
            isStaked: true,
            rewardMultiplier: nftCollections[nftContract].rewardMultiplier
        });
        
        userStakedNFTs[msg.sender].push(tokenId);
        
        emit NFTStaked(msg.sender, nftContract, tokenId, duration, nftCollections[nftContract].rewardMultiplier);
    }
    
    function unstakeNFT(
        address nftContract,
        uint256 tokenId
    ) external nonReentrant {
        require(stakedNFTs[nftContract][tokenId].isStaked, "NFT not staked");
        require(stakedNFTs[nftContract][tokenId].staker == msg.sender, "Not staker");
        
        // Проверка времени стейкинга
        require(block.timestamp >= stakedNFTs[nftContract][tokenId].stakeTime + stakedNFTs[nftContract][tokenId].stakingDuration, "Staking period not ended");
        
        // Возврат NFT
        ERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        
        // Сброс стейкинга
        stakedNFTs[nftContract][tokenId].isStaked = false;
        
        // Удаление из списка пользователя
        for (uint256 i = 0; i < userStakedNFTs[msg.sender].length; i++) {
            if (userStakedNFTs[msg.sender][i] == tokenId) {
                userStakedNFTs[msg.sender][i] = userStakedNFTs[msg.sender][userStakedNFTs[msg.sender].length - 1];
                userStakedNFTs[msg.sender].pop();
                break;
            }
        }
        
        emit NFTUnstaked(msg.sender, nftContract, tokenId, 0); // Награды будут рассчитаны отдельно
    }
    
    function getStakedNFTs(address user) external view returns (uint256[] memory) {
        return userStakedNFTs[user];
    }
    
    function getCollectionInfo(address nftContract) external view returns (NFTCollection memory) {
        return nftCollections[nftContract];
    }
    
    function getStakeInfo(address nftContract, uint256 tokenId) external view returns (NFTStake memory) {
        return stakedNFTs[nftContract][tokenId];
    }
}
