// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./GymToken.sol";

contract GymICO is AccessControl {
    GymToken public token; // Reference to the GymToken contract
    uint256 public tokenPrice; // Price per GymToken in wei
    uint256 public tokensSold; // Track total tokens sold during the ICO

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event Withdrawn(address indexed recipient, uint256 amount);

    // Modify the constructor to grant the manager role to the deployer
    constructor(address _tokenAddress, uint256 _tokenPrice, address _manager) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_manager != address(0), "Invalid manager address");

        token = GymToken(_tokenAddress);
        tokenPrice = _tokenPrice;

        // Grant the deployer the MANAGER_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, _manager);
        _grantRole(MANAGER_ROLE, _manager);
    }

    // Modifier to check if the caller is a manager
    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a manager");
        _;
    }

    // Buy tokens during the ICO
    function buyTokens() external payable {
        require(msg.value > 0, "Must send ETH to buy tokens");

        uint256 tokenAmount = msg.value / tokenPrice; // Calculate tokens to be purchased
        require(
            token.balanceOf(address(this)) >= tokenAmount,
            "Not enough tokens in contract"
        );

        tokensSold += tokenAmount;

        // Transfer the tokens to the buyer
        token.transfer(msg.sender, tokenAmount);

        emit TokensPurchased(msg.sender, tokenAmount, msg.value);
    }

    // Withdraw funds collected during the ICO
    function withdrawFunds() external onlyManager {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        payable(msg.sender).transfer(balance);
        emit Withdrawn(msg.sender, balance);
    }

    // Set the price of tokens (manager only)
    function setTokenPrice(uint256 _tokenPrice) external onlyManager {
        require(_tokenPrice > 0, "Price must be greater than 0");
        tokenPrice = _tokenPrice;
    }
}
