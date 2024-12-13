const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Gym Contracts", function () {
  async function deployFixture() {
    const [manager, staff, member, trainer, otherAccount] =
      await ethers.getSigners();

    // Deploy GymToken
    const GymToken = await ethers.getContractFactory("GymToken");
    const gymToken = await GymToken.deploy(manager.address);

    // Deploy GymICO
    const GymICO = await ethers.getContractFactory("GymICO");
    const tokenPrice = ethers.parseEther("0.001");
    const gymICO = await GymICO.deploy(
      await gymToken.getAddress(),
      tokenPrice,
      manager.address
    );

    // Get roles
    const MANAGER_ROLE = await gymToken.MANAGER_ROLE();
    const STAFF_ROLE = await gymToken.STAFF_ROLE();
    const MEMBER_ROLE = await gymToken.MEMBER_ROLE();
    const TRAINER_ROLE = await gymToken.TRAINER_ROLE();

    return {
      gymToken,
      gymICO,
      manager,
      staff,
      member,
      trainer,
      otherAccount,
      tokenPrice,
      MANAGER_ROLE,
      STAFF_ROLE,
      MEMBER_ROLE,
      TRAINER_ROLE,
    };
  }

  describe("Deployment", function () {
    it("Should deploy successfully", async function () {
      const { gymToken, gymICO } = await loadFixture(deployFixture);
      expect(await gymToken.getAddress()).to.be.properAddress;
      expect(await gymICO.getAddress()).to.be.properAddress;
    });

    it("Should set the right manager", async function () {
      const { gymToken, manager, MANAGER_ROLE } = await loadFixture(
        deployFixture
      );
      expect(await gymToken.hasRole(MANAGER_ROLE, manager.address)).to.be.true;
    });

    it("Should set correct initial supply", async function () {
      const { gymToken, manager } = await loadFixture(deployFixture);
      const decimal = await gymToken.decimal();
      const expectedSupply = 1000000n * 10n ** BigInt(decimal);
      expect(await gymToken.balanceOf(manager.address)).to.equal(
        expectedSupply
      );
    });
  });

  describe("Role Management", function () {
    it("Should allow manager to add staff role", async function () {
      const { gymToken, manager, staff, STAFF_ROLE } = await loadFixture(
        deployFixture
      );
      await gymToken.connect(manager).addUserToRole(staff.address, STAFF_ROLE);
      expect(await gymToken.hasRole(STAFF_ROLE, staff.address)).to.be.true;
    });

    it("Should not allow non-manager to add roles", async function () {
      const { gymToken, staff, member, MEMBER_ROLE, MANAGER_ROLE } =
        await loadFixture(deployFixture);
      await expect(
        gymToken.connect(staff).addUserToRole(member.address, MEMBER_ROLE)
      ).to.be.revertedWith(
        `AccessControl: account ${staff.address.toLowerCase()} is missing role ${MANAGER_ROLE}`
      );
    });
  });
  describe("Staff Payment", function () {
    it("Should allow manager to pay staff", async function () {
      const { gymToken, manager, staff, STAFF_ROLE } = await loadFixture(
        deployFixture
      );

      // Add staff role
      await gymToken.connect(manager).addUserToRole(staff.address, STAFF_ROLE);

      // Payment amount
      const payAmount = 100n * 10n ** 2n; // 100 tokens with 2 decimals

      // Get initial balances
      const initialManagerBalance = await gymToken.balanceOf(manager.address);
      const initialStaffBalance = await gymToken.balanceOf(staff.address);

      // using change token balance
      await expect(
        gymToken.connect(manager).payStaff(staff.address, payAmount)
      ).to.changeTokenBalances(
        gymToken,
        [manager, staff],
        [-payAmount, payAmount]
      );
    });
  });
  describe("Membership Operations", function () {
    it("Should allow member to purchase membership", async function () {
      const { gymToken, manager, member, MEMBER_ROLE } = await loadFixture(
        deployFixture
      );

      // Add member role
      await gymToken
        .connect(manager)
        .addUserToRole(member.address, MEMBER_ROLE);

      // Transfer some tokens to member for membership purchase
      const transferAmount = 100n * 10n ** 2n; // 100 tokens
      await gymToken.connect(manager).transfer(member.address, transferAmount);

      // Purchase membership
      await gymToken.connect(member).purchaseMembership(0); // 0 for Monthly

      expect(
        await gymToken.getRemainingMembershipTime(member.address)
      ).to.be.gt(0);
    });
  });

  describe("ICO Operations", function () {
    it("Should allow users to buy tokens", async function () {
      const { gymICO, gymToken, manager, otherAccount, tokenPrice } =
        await loadFixture(deployFixture);

      // Transfer tokens to ICO contract first
      // Using 2 decimals as per GymToken contract
      const transferAmount = 1000n * 10n ** 2n; // 1000 tokens with 2 decimals
      await gymToken
        .connect(manager)
        .transfer(await gymICO.getAddress(), transferAmount);

      // Buy tokens
      const buyAmount = ethers.parseEther("0.1"); // 0.1 ETH
      await gymICO.connect(otherAccount).buyTokens({ value: buyAmount });

      expect(await gymToken.balanceOf(otherAccount.address)).to.be.greaterThan(
        0
      );
    });
  });
  describe("Training Sessions", function () {
    it("Should allow trainer to create a training session", async function () {
      const { gymToken, manager, trainer, TRAINER_ROLE } = await loadFixture(
        deployFixture
      );

      // Add trainer role
      await gymToken
        .connect(manager)
        .addUserToRole(trainer.address, TRAINER_ROLE);

      // Set future timestamp for session
      const sessionTime = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now
      const sessionCost = 50n * 10n ** 2n; // 50 tokens

      await gymToken
        .connect(trainer)
        .createTrainingSession("Yoga Class", sessionTime, sessionCost);

      const sessionId = 1; // First session
      const [id, name] = await gymToken.trainingSessions(sessionId);
      expect(id).to.equal(1n);
      expect(name).to.equal("Yoga Class");
    });

    it("Should allow member to register for training session", async function () {
      const { gymToken, manager, trainer, member, TRAINER_ROLE, MEMBER_ROLE } =
        await loadFixture(deployFixture);

      // Setup roles
      await gymToken
        .connect(manager)
        .addUserToRole(trainer.address, TRAINER_ROLE);
      await gymToken
        .connect(manager)
        .addUserToRole(member.address, MEMBER_ROLE);

      // Transfer tokens to member
      const tokens = 100n * 10n ** 2n;
      await gymToken.connect(manager).transfer(member.address, tokens);

      // Create session
      const sessionTime = Math.floor(Date.now() / 1000) + 86400;
      const sessionCost = 50n * 10n ** 2n;
      await gymToken
        .connect(trainer)
        .createTrainingSession("Yoga", sessionTime, sessionCost);

      // Register for session
      await gymToken.connect(member).registerForTrainingSession(1);

      // Check registration
      const participants = await gymToken.sessionParticipants(1, 0);
      expect(participants).to.equal(member.address);
    });
  });
  describe("Challenge System", function () {
    it("Should allow manager to create a challenge", async function () {
      const { gymToken, manager } = await loadFixture(deployFixture);

      const reward = 100n * 10n ** 2n; // 100 tokens
      await gymToken
        .connect(manager)
        .createChallenge("Weight Loss Challenge", reward);

      const [name, rewardAmount] = await gymToken.getChallengeDetails(1);
      expect(name).to.equal("Weight Loss Challenge");
      expect(rewardAmount).to.equal(reward);
    });

    it("Should allow member to register and complete challenge", async function () {
      const { gymToken, manager, member, MEMBER_ROLE } = await loadFixture(
        deployFixture
      );

      // Add member role
      await gymToken
        .connect(manager)
        .addUserToRole(member.address, MEMBER_ROLE);

      // Create challenge
      const reward = 100n * 10n ** 2n;
      await gymToken
        .connect(manager)
        .createChallenge("Weight Loss Challenge", reward);

      // Register for challenge
      await gymToken.connect(member).registerForChallenge(1);

      // Complete challenge and check reward
      const initialBalance = await gymToken.balanceOf(member.address);
      await gymToken.connect(member).completeChallenge();
      const finalBalance = await gymToken.balanceOf(member.address);

      expect(finalBalance - initialBalance).to.equal(reward);
    });
  });

  describe("Referral System", function () {
    it("Should reward referrer with bonus tokens", async function () {
      const { gymToken, manager, member, MEMBER_ROLE } = await loadFixture(
        deployFixture
      );

      // Setup member with active membership
      await gymToken
        .connect(manager)
        .addUserToRole(member.address, MEMBER_ROLE);
      const transferAmount = 100n * 10n ** 2n;
      await gymToken.connect(manager).transfer(member.address, transferAmount);
      await gymToken.connect(member).purchaseMembership(0); // Monthly membership

      // Process referral
      const initialBalance = await gymToken.balanceOf(member.address);
      await gymToken.connect(manager).rewardReferral(member.address);
      const finalBalance = await gymToken.balanceOf(member.address);

      const referralReward = await gymToken.REFERRAL_REWARD();
      expect(finalBalance - initialBalance).to.equal(referralReward);
    });
  });

  describe("Token Transfer Restrictions", function () {
    it("Should restrict certain operations when paused", async function () {
      const { gymToken, manager, staff } = await loadFixture(deployFixture);

      await gymToken.connect(manager).pause();

      const payAmount = 100n * 10n ** 2n;
      await expect(
        gymToken.connect(manager).payStaff(staff.address, payAmount)
      ).to.be.revertedWith("Pausable: paused"); // Updated to match OpenZeppelin
    });

    it("Should only allow manager to mint new tokens", async function () {
      const { gymToken, staff, member, MANAGER_ROLE } = await loadFixture(
        deployFixture
      );

      const mintAmount = 1000n * 10n ** 2n;
      // Using the standard AccessControl error message
      await expect(
        gymToken.connect(staff).mintTokens(member.address, mintAmount)
      ).to.be.revertedWith(
        `AccessControl: account ${staff.address.toLowerCase()} is missing role ${MANAGER_ROLE}`
      );
    });
  });
  describe("Pausable Functionality", function () {
    it("Should start in unpaused state", async function () {
      const { gymToken } = await loadFixture(deployFixture);
      expect(await gymToken.paused()).to.be.false;
    });

    it("Should allow manager to pause and emit event", async function () {
      const { gymToken, manager } = await loadFixture(deployFixture);

      // Check for Paused event
      await expect(gymToken.connect(manager).pause())
        .to.emit(gymToken, "Paused")
        .withArgs(manager.address);

      // Verify paused state
      expect(await gymToken.paused()).to.be.true;
    });

    it("Should allow manager to unpause and emit event", async function () {
      const { gymToken, manager } = await loadFixture(deployFixture);

      // Pause first
      await gymToken.connect(manager).pause();

      // Check for Unpaused event
      await expect(gymToken.connect(manager).unpause())
        .to.emit(gymToken, "Unpaused")
        .withArgs(manager.address);

      // Verify unpaused state
      expect(await gymToken.paused()).to.be.false;
    });

    it("Should prevent non-manager from pausing", async function () {
      const { gymToken, staff, MANAGER_ROLE } = await loadFixture(
        deployFixture
      );

      await expect(gymToken.connect(staff).pause()).to.be.revertedWith(
        `AccessControl: account ${staff.address.toLowerCase()} is missing role ${MANAGER_ROLE}`
      );
    });

    it("Should allow operations after unpausing", async function () {
      const { gymToken, manager, member } = await loadFixture(deployFixture);

      // Pause and then unpause
      await gymToken.connect(manager).pause();
      await gymToken.connect(manager).unpause();

      // Try operation
      const transferAmount = 100n * 10n ** 2n;
      await expect(
        gymToken.connect(manager).transfer(member.address, transferAmount)
      ).to.not.be.reverted;
    });
  });
});
