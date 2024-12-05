// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract GymToken is ERC20, Pausable, AccessControl {
    uint8 public constant decimal = 2;
    uint256 public constant INITIAL_SUPPLY = 1000000 * (10 ** decimal);

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant STAFF_ROLE = keccak256("STAFF_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant TRAINER_ROLE = keccak256("TRAINER_ROLE");

    // Constant reward amount for referrals (e.g., 10 tokens for every referral)
    uint256 public constant REFERRAL_REWARD = 10 * (10 ** decimal);

    enum MEMBERSHIP_TYPE {
        Monthly,
        Quarterly,
        Annual
    }

    mapping(MEMBERSHIP_TYPE => uint256) public membershipPrices; // Membership prices by type
    mapping(address => uint256) public membershipExpiry; // Track expiry timestamps for members
    mapping(address => uint256) public referralBonuses;

    event MembershipPurchased(
        address indexed member,
        MEMBERSHIP_TYPE membershipType,
        uint256 duration
    );
    event ReferralRewarded(address indexed referrer, uint256 amount);
    event StaffPaid(address indexed staff, uint256 amount);

    constructor(address manager) ERC20("GymToken", "GYM") {
        // Assign the manager both admin and manager roles
        _grantRole(DEFAULT_ADMIN_ROLE, manager);
        _grantRole(MANAGER_ROLE, manager);

        // Initialize membership prices
        membershipPrices[MEMBERSHIP_TYPE.Monthly] = 50 * (10 ** decimal); // 50 GYM tokens
        membershipPrices[MEMBERSHIP_TYPE.Quarterly] = 140 * (10 ** decimal); // 140 GYM tokens
        membershipPrices[MEMBERSHIP_TYPE.Annual] = 500 * (10 ** decimal); // 500 GYM tokens

        // Mint initial token supply to the manager
        _mint(manager, INITIAL_SUPPLY);
    }

    // Modifier to check if the caller is a manager
    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a manager");
        _;
    }

    // Modifier to check if the caller is a member
    modifier onlyMember() {
        require(hasRole(MEMBER_ROLE, msg.sender), "Caller is not a member");
        _;
    }

    // Modifier to validate non-zero address
    modifier validAddress(address account) {
        require(account != address(0), "Invalid address");
        _;
    }

    // Allows managers to pause all token-related activities
    function pause() public onlyRole(MANAGER_ROLE) {
        _pause();
    }

    // Allows managers to unpause token activities
    function unpause() public onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    // Role management functions
    function addUserToRole(
        address account,
        bytes32 role
    ) external onlyRole(MANAGER_ROLE) validAddress(account) {
        grantRole(role, account);
    }

    function removeUserFromRole(
        address account,
        bytes32 role
    ) external onlyRole(MANAGER_ROLE) validAddress(account) {
        revokeRole(role, account);
    }

    // Allows managers to transfer wages to staff
    function payStaff(
        address staff,
        uint256 amount
    ) public whenNotPaused onlyRole(MANAGER_ROLE) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _transfer(msg.sender, staff, amount);
    }

    // Referral bonus reward mechanism
    function rewardReferral(
        address referrer
    ) public whenNotPaused onlyRole(MANAGER_ROLE) {
        // Ensure that the referrer has an active membership
        require(
            block.timestamp < membershipExpiry[referrer],
            "Referrer membership expired"
        );

        // Reward the referrer with the specified amount
        referralBonuses[referrer] += REFERRAL_REWARD;
        _mint(referrer, REFERRAL_REWARD);

        emit ReferralRewarded(referrer, REFERRAL_REWARD);
    }

    // Members can purchase memberships by burning tokens
    function purchaseMembership(
        MEMBERSHIP_TYPE membershipType
    ) public whenNotPaused onlyMember {
        uint256 price = membershipPrices[membershipType];
        require(balanceOf(msg.sender) >= price, "Insufficient balance");

        _burn(msg.sender, price);

        uint256 duration;

        // Set the duration based on membership type
        if (membershipType == MEMBERSHIP_TYPE.Monthly) {
            duration = 30 days;
        } else if (membershipType == MEMBERSHIP_TYPE.Quarterly) {
            duration = 90 days;
        } else if (membershipType == MEMBERSHIP_TYPE.Annual) {
            duration = 365 days;
        } else {
            revert("Invalid membership type");
        }

        // If the member has an existing membership, extend it; otherwise, set a new expiration time
        if (block.timestamp < membershipExpiry[msg.sender]) {
            membershipExpiry[msg.sender] += duration;
        } else {
            membershipExpiry[msg.sender] = block.timestamp + duration;
        }

        emit MembershipPurchased(msg.sender, membershipType, duration);
    }

    // Check remaining membership time
    function getRemainingMembershipTime(
        address member
    ) public view returns (uint256) {
        if (block.timestamp >= membershipExpiry[member]) {
            return 0;
        } else {
            return membershipExpiry[member] - block.timestamp;
        }
    }
}

// examples:
// staff address: 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
// example member address: 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
// personal trainer address: 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB
