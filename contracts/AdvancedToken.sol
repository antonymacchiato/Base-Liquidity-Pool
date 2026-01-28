// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AdvancedToken is ERC20, Ownable {
    struct TokenType {
        string name;
        uint256 riskLevel;
        uint256 rewardMultiplier;
        bool enabled;
        uint256 maxSupply;
    }
    
    mapping(string => TokenType) public tokenTypes;
    mapping(address => string) public userTokenType;
    
    event TokenTypeCreated(string indexed tokenType, uint256 riskLevel, uint256 rewardMultiplier);
    event TokenTypeUpdated(string indexed tokenType, uint256 riskLevel, uint256 rewardMultiplier);
    event UserTokenTypeAssigned(address indexed user, string indexed tokenType);
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function createTokenType(
        string memory tokenType,
        uint256 riskLevel,
        uint256 rewardMultiplier,
        uint256 maxSupply
    ) external onlyOwner {
        require(bytes(tokenType).length > 0, "Token type cannot be empty");
        require(riskLevel <= 10000, "Risk level too high");
        require(rewardMultiplier <= 10000, "Reward multiplier too high");
        
        tokenTypes[tokenType] = TokenType({
            name: tokenType,
            riskLevel: riskLevel,
            rewardMultiplier: rewardMultiplier,
            enabled: true,
            maxSupply: maxSupply
        });
        
        emit TokenTypeCreated(tokenType, riskLevel, rewardMultiplier);
    }
    
    function updateTokenType(
        string memory tokenType,
        uint256 riskLevel,
        uint256 rewardMultiplier
    ) external onlyOwner {
        require(tokenTypes[tokenType].name.length > 0, "Token type not found");
        require(riskLevel <= 10000, "Risk level too high");
        require(rewardMultiplier <= 10000, "Reward multiplier too high");
        
        tokenTypes[tokenType].riskLevel = riskLevel;
        tokenTypes[tokenType].rewardMultiplier = rewardMultiplier;
        
        emit TokenTypeUpdated(tokenType, riskLevel, rewardMultiplier);
    }
    
    function assignUserTokenType(
        address user,
        string memory tokenType
    ) external onlyOwner {
        require(tokenTypes[tokenType].name.length > 0, "Token type not found");
        require(tokenTypes[tokenType].enabled, "Token type not enabled");
        
        userTokenType[user] = tokenType;
        
        emit UserTokenTypeAssigned(user, tokenType);
    }
    
    function getUserTokenType(address user) external view returns (string memory) {
        return userTokenType[user];
    }
    
    function getTokenTypeInfo(string memory tokenType) external view returns (TokenType memory) {
        return tokenTypes[tokenType];
    }
    
    function getUserTokenInfo(address user) external view returns (string memory, TokenType memory) {
        string memory userType = userTokenType[user];
        TokenType memory typeInfo = tokenTypes[userType];
        return (userType, typeInfo);
    }
}
