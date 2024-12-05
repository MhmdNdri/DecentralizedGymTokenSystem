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

    struct Challenge {
        uint256 id;
        string name;
        uint256 reward;
    }

    struct TrainingSession {
        uint256 id;
        string name;
        uint256 date;
        uint256 cost;
        address trainer;
    }

    // Mapping of user registrations for challenges
    mapping(address => uint256) public userChallengeRegistrations;
    mapping(MEMBERSHIP_TYPE => uint256) public membershipPrices;
    mapping(address => uint256) public membershipExpiry;
    mapping(address => uint256) public referralBonuses;

    // Challenges mapping by ID
    mapping(uint256 => Challenge) public challenges;
    uint256 public challengeCount;

    // Mapping of training sessions
    mapping(uint256 => TrainingSession) public trainingSessions;
    mapping(uint256 => address[]) public sessionParticipants;
    uint256 public sessionCount;

    event MembershipPurchased(
        address indexed member,
        MEMBERSHIP_TYPE membershipType,
        uint256 duration
    );
    event ReferralRewarded(address indexed referrer, uint256 amount);
    event StaffPaid(address indexed staff, uint256 amount);
    event ChallengeCreated(
        uint256 indexed challengeId,
        string challengeName,
        uint256 reward
    );
    event ChallengeRegistered(
        address indexed member,
        uint256 indexed challengeId
    );
    event ChallengeCompleted(
        address indexed member,
        uint256 indexed challengeId,
        uint256 reward
    );
    event TrainingSessionCreated(
        uint256 indexed sessionId,
        string name,
        uint256 date,
        uint256 cost,
        address trainer
    );
    event TrainingSessionRegistered(
        address indexed member,
        uint256 indexed sessionId
    );

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
    ) external onlyRole(MANAGER_ROLE) {
        grantRole(role, account);
    }

    function removeUserFromRole(
        address account,
        bytes32 role
    ) external onlyRole(MANAGER_ROLE) {
        revokeRole(role, account);
    }

    // Allows managers to transfer wages to staff
    function payStaff(
        address staff,
        uint256 amount
    ) public whenNotPaused onlyRole(MANAGER_ROLE) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(hasRole(STAFF_ROLE, staff), "his is not a staff address");
        _transfer(msg.sender, staff, amount);
    }

    // Referral bonus reward mechanism
    function rewardReferral(
        address referrer
    ) public whenNotPaused onlyRole(MANAGER_ROLE) {
        require(
            block.timestamp < membershipExpiry[referrer],
            "Referrer membership expired"
        );
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

        if (membershipType == MEMBERSHIP_TYPE.Monthly) {
            duration = 30 days;
        } else if (membershipType == MEMBERSHIP_TYPE.Quarterly) {
            duration = 90 days;
        } else if (membershipType == MEMBERSHIP_TYPE.Annual) {
            duration = 365 days;
        } else {
            revert("Invalid membership type");
        }

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

    // Public mint function restricted to managers
    function mintTokens(
        address to,
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        require(to != address(0), "Invalid address");
        _mint(to, amount);
    }

    // Challenge functions

    // Create a new challenge
    function createChallenge(
        string memory name,
        uint256 reward
    ) external onlyManager {
        challengeCount++;
        challenges[challengeCount] = Challenge({
            id: challengeCount,
            name: name,
            reward: reward
        });

        emit ChallengeCreated(challengeCount, name, reward);
    }

    // Register for a challenge
    function registerForChallenge(uint256 challengeId) external onlyMember {
        // Ensure the challenge exists
        Challenge storage challenge = challenges[challengeId];
        require(challenge.id != 0, "Challenge does not exist");

        // Register the user for the challenge
        userChallengeRegistrations[msg.sender] = challengeId;

        emit ChallengeRegistered(msg.sender, challengeId);
    }

    // Complete a challenge and reward the member
    function completeChallenge() external onlyMember {
        uint256 challengeId = userChallengeRegistrations[msg.sender];
        require(challengeId != 0, "No active challenge registered");

        Challenge storage challenge = challenges[challengeId];

        // Reward the member
        _mint(msg.sender, challenge.reward);

        // Clear the member's registration for the challenge
        userChallengeRegistrations[msg.sender] = 0;

        emit ChallengeCompleted(msg.sender, challengeId, challenge.reward);
    }

    // View a challenge's details by ID
    function getChallengeDetails(
        uint256 challengeId
    ) external view returns (string memory, uint256) {
        Challenge storage challenge = challenges[challengeId];
        return (challenge.name, challenge.reward);
    }
    // Training session functions
    // Create a new training session
    function createTrainingSession(
        string memory name,
        uint256 date,
        uint256 cost
    ) external onlyRole(TRAINER_ROLE) {
        require(date > block.timestamp, "Date must be in the future");
        sessionCount++;
        trainingSessions[sessionCount] = TrainingSession({
            id: sessionCount,
            name: name,
            date: date,
            cost: cost,
            trainer: msg.sender
        });
        emit TrainingSessionCreated(sessionCount, name, date, cost, msg.sender);
    }
    //Register for a Training Session:
    function registerForTrainingSession(uint256 sessionId) external onlyMember {
        TrainingSession storage session = trainingSessions[sessionId];
        require(session.id != 0, "Session does not exist");
        require(balanceOf(msg.sender) >= session.cost, "Insufficient balance");
        _burn(msg.sender, session.cost);
        sessionParticipants[sessionId].push(msg.sender);
        emit TrainingSessionRegistered(msg.sender, sessionId);
    }
    //get All training sessions
    //this function is not neccessary and I think due to gas we can remove it
    function getAllTrainingSessions()
        external
        view
        returns (uint256[] memory, string[] memory)
    {
        uint256 totalSessions = sessionCount;
        uint256[] memory ids = new uint256[](totalSessions);
        string[] memory names = new string[](totalSessions);

        for (uint256 i = 1; i <= totalSessions; i++) {
            ids[i - 1] = trainingSessions[i].id;
            names[i - 1] = trainingSessions[i].name;
        }

        return (ids, names);
    }
}
// addresses:
// Manager: 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
// staff: 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
// Member: 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
// personal trainer: 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB
