import { expect } from "chai";
import { ethers } from "hardhat";

describe("ZetbaTicketing Smart Contract", function () {
  let zetbaTicketing, owner, eventCreator, user1, user2;

  beforeEach(async function () {
    [owner, eventCreator, user1, user2] = await ethers.getSigners();

    const ZetbaTicketing = await ethers.getContractFactory("ZetbaTicketing");
    zetbaTicketing = await ZetbaTicketing.deploy();
    await zetbaTicketing.deployed();
  });

  it("should deploy correctly and set initial values", async function () {
    const platformOwner = await zetbaTicketing.platformOwner();
    const platformFeePercent = await zetbaTicketing.platformFeePercent();

    expect(platformOwner).to.equal(owner.address);
    expect(platformFeePercent).to.equal(2); // 2% platform fee
  });

  describe("Occasion Creation", function () {
    it("should allow event creator to create an occasion", async function () {
      const tx = await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash123",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );
      await expect(tx).to.emit(zetbaTicketing, "OccasionCreated");
      const occasion = await zetbaTicketing.occasions(0);

      expect(occasion.creator).to.equal(eventCreator.address);
      expect(occasion.maxTicketsPerUser).to.equal(5);
    });

    it("should revert if the event date is in the past", async function () {
      await expect(
        zetbaTicketing.connect(eventCreator).createOccasion("ipfsHash", 1000, 5)
      ).to.be.revertedWith("Event date must be in the future");
    });
  });

  describe("Ticket Model Management", function () {
    it("should add a ticket model to an occasion", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      const occasion = await zetbaTicketing.occasions(0);
      const ticketModel = occasion.ticketModels[0];

      expect(ticketModel.ticketType).to.equal("VIP");
      expect(ticketModel.price).to.equal(ethers.utils.parseEther("0.1"));
      expect(ticketModel.totalTickets).to.equal(100);
    });

    it("should update a ticket model", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      await zetbaTicketing
        .connect(eventCreator)
        .updateTicketModel(
          0,
          0,
          "Super VIP",
          ethers.utils.parseEther("0.2"),
          false,
          true,
          true
        );

      const occasion = await zetbaTicketing.occasions(0);
      const ticketModel = occasion.ticketModels[0];

      expect(ticketModel.ticketType).to.equal("Super VIP");
      expect(ticketModel.price).to.equal(ethers.utils.parseEther("0.2"));
    });

    it("should deactivate a ticket model", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      await zetbaTicketing.connect(eventCreator).deactivateTicketModel(0, 0);

      const occasion = await zetbaTicketing.occasions(0);
      const ticketModel = occasion.ticketModels[0];
      expect(ticketModel.isActive).to.be.false;
    });
  });

  describe("Ticket Purchasing and Refunds", function () {
    it("should allow users to buy a ticket", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      const tx = await zetbaTicketing.connect(user1).buyTicket(0, 0, {
        value: ethers.utils.parseEther("0.102"), // 0.1 + platform fee
      });

      await expect(tx).to.emit(zetbaTicketing, "TicketMinted");
      const ticket = await zetbaTicketing.mintedTickets(1); // Assuming first ticket

      expect(ticket.owner).to.equal(user1.address);
      expect(ticket.price).to.equal(ethers.utils.parseEther("0.1"));
    });

    it("should allow ticket refunds", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      await zetbaTicketing.connect(user1).buyTicket(0, 0, {
        value: ethers.utils.parseEther("0.102"), // 0.1 + platform fee
      });

      const tx = await zetbaTicketing.connect(user1).refundTicket(1);
      await expect(tx).to.emit(zetbaTicketing, "TicketRefunded");

      const ticket = await zetbaTicketing.mintedTickets(1);
      expect(ticket.isBurnt).to.be.true;
    });
  });

  describe("Check-in and Payout", function () {
    it("should allow event creator to check-in tickets", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      await zetbaTicketing.connect(user1).buyTicket(0, 0, {
        value: ethers.utils.parseEther("0.102"), // 0.1 + platform fee
      });

      const tx = await zetbaTicketing.connect(eventCreator).checkInTicket(0, 1);
      await expect(tx).to.emit(zetbaTicketing, "CheckedIn");

      const ticket = await zetbaTicketing.mintedTickets(1);
      expect(ticket.hasCheckedIn).to.be.true;
    });

    it("should payout funds to the event creator after the event", async function () {
      await zetbaTicketing
        .connect(eventCreator)
        .createOccasion(
          "ipfsHash",
          (await ethers.provider.getBlock("latest")).timestamp + 1000,
          5
        );

      await zetbaTicketing
        .connect(eventCreator)
        .addTicketModel(
          0,
          "VIP",
          ethers.utils.parseEther("0.1"),
          true,
          true,
          true,
          100
        );

      await zetbaTicketing.connect(user1).buyTicket(0, 0, {
        value: ethers.utils.parseEther("0.102"), // 0.1 + platform fee
      });

      // Fast forward time to after the event
      await ethers.provider.send("evm_increaseTime", [100000]);
      await ethers.provider.send("evm_mine");

      const tx = await zetbaTicketing
        .connect(eventCreator)
        .payoutToEventCreator(0);
      await expect(tx).to.emit(zetbaTicketing, "EventFundsPaidOut");

      const funds = await zetbaTicketing.fundsByEventId(0);
      expect(funds).to.equal(0);
    });
  });
});
