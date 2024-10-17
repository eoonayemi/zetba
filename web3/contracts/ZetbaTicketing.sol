// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@thirdweb-dev/contracts/base/ERC721Base.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@thirdweb-dev/contracts/extension/Permissions.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ZetbaTicketings
 * @dev A decentralized event ticketing system using ERC721 tokens for tickets.
 * This contract includes role-based access control, event management, ticket minting, and check-in functionalities.
 */
contract ZetbaTicketing is ERC721Base, Permissions, ReentrancyGuard {
    using Math for uint256;

    uint256 public totalEventCreators;
    uint256 public totalMintedTickets;
    uint256 internal occasionIdCount;
    address public platformOwner;
    uint256 public platformFeePercent;
    uint256 internal ticketsForSaleIdCount;

    // Events
    event OccasionCreated(uint256 indexed _occasionId, address indexed _creator, string _ipfsHash);
    event TicketMinted(address indexed _owner, uint256 indexed _occasionId, uint256 _ticketModelId, uint256 _price);
    event CheckedIn(uint256 indexed _ticketId, uint256 _occasionId);
    event OccasionDeactivated(uint256 indexed _occasionId);
    event OccasionDeleted(uint256 indexed _occasionId);
    event TicketOfferedForSale(uint256 indexed _ticketId, address indexed _owner);
    event TicketResold(uint256 indexed _ticketId, address indexed _seller, address indexed _newOwner);
    event EventFundsPaidOut(address indexed _eventCreator, uint256 _amtPaidOut);
    event TicketModelUpdated(uint256 indexed _occasionId, uint256 indexed _ticketModelId);
    event TicketModelDeactivated(uint256 indexed _occasionId, uint256 indexed _ticketModelId);
    event TicketModelDeleted(uint256 indexed _occasionId, uint256 indexed _ticketModelId);

    // Custom Errors
    error InvalidOccasionId(uint256 occasionId);
    error OccasionNotActive(uint256 occasionId);
    error CallerNotEventCreator();
    error CallerNotTicketOwner();
    error EventNotTransferrable();
    error TicketAlreadyCheckedIn(uint256 ticketId);
    error TicketNotRefundable(uint256 ticketId);
    error InsufficientFunds();
    error TicketModelNotActive(uint256 ticketModelId);

    struct MintedTicket {
        uint256 _id;
        uint256 occasionId;
        uint256 ticketModelId;
        uint256 price;
        uint256 platformFee;
        address owner;
        bool isBurnt;
        bool isForSale;
        bool hasCheckedIn;
        string ticketType;
        string ipfsHash;
}

    struct TicketModel {
        uint256 occasionId;
        uint256 price;
        uint256 soldTickets;
        uint256 totalTickets;
        bool isTransferrable;
        bool isResellable;
        bool isRefundable;
        bool isActive;
        string ticketType;
    }

    struct Occasion {
        uint256 _id;
        uint256 _date;
        uint256 totalTickets;
        uint256 soldTickets;
        uint256 maxTicketsPerUser;
        address creator;
        bool isActive;
        bool isDeleted;
        bool isPaidOut;
        TicketModel[] ticketModels;
    }

    mapping(uint256 => Occasion) public occasions;
    mapping(uint256 => MintedTicket) public mintedTickets;
    mapping(address => uint256) public userToTickets;
    mapping(uint256 => uint256) public fundsByEventId;

    // Modifiers
    modifier onlyActiveOccasion(uint256 _occasionId) {
        if (!occasions[_occasionId].isActive) revert OccasionNotActive(_occasionId);
        _;
    }

    modifier onlyEventCreator(uint256 _occasionId) {
        if (occasions[_occasionId].creator != msg.sender) revert CallerNotEventCreator();
        _;
    }

    modifier onlyTicketOwner(uint256 _ticketId) {
        if (mintedTickets[_ticketId].owner != msg.sender) revert CallerNotTicketOwner();
        _;
    }

    modifier onlyExistingTicket(uint256 _ticketId) {
        require(_exists(_ticketId), "Ticket does not exist");
        _;
    }

    constructor()
        ERC721Base(
            msg.sender,       // Contract admin
            "ZetbaTicket",    // Token name
            "ZKT",            // Token symbol
            msg.sender,       // Royalty recipient
            100               // Royalty points
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        platformOwner = msg.sender;
        platformFeePercent = 2;
    }


    /**
     * @dev Create a new occasion.
     * @param _ipfsHash IPFS hash of occasion metadata.
     * @param _date date of the occasion
     * @param _maxTicketsPerUser maximum number of tickets that can be purchased by a user
     * @return _occasionId Newly created occasion's ID.
     */
    function createOccasion(string calldata _ipfsHash, uint256 _date, uint256 _maxTicketsPerUser) public returns (uint256) {
        require(_date > block.timestamp, "Event date must be in the future");

        Occasion storage occasion = occasions[occasionIdCount];

        occasion._id = occasionIdCount;
        occasion.creator = msg.sender;
        occasion._date = _date;
        occasion.isActive = true;
        occasion.isDeleted = false;
        occasion.maxTicketsPerUser = _maxTicketsPerUser;

        occasionIdCount++;

        emit OccasionCreated(occasionIdCount, msg.sender, _ipfsHash);
        return occasionIdCount - 1;
    }

    /**
     * @dev Create a new occasion.
     * @param _ipfsHash IPFS hash of occasion metadata.
     * @param _date date of the occasion
     * @return _occasionId Newly created occasion's ID.
     */
    function createOccasion(string calldata _ipfsHash, uint256 _date) external returns (uint256) {
        return createOccasion(_ipfsHash, _date, 1);
    }

    /**
     * @dev Update an existing occasion.
     * @param _occasionId ID of the occasion to update.
     * @param _ipfsHash New IPFS hash of occasion metadata.
     * @param _date New date for the occasion.
     * @param _maxTicketsPerUser New maximum number of tickets that cab be purchased by user
     */
    function updateOccasion(
        uint256 _occasionId,
        string calldata _ipfsHash,
        uint256 _date,
        uint256 _maxTicketsPerUser
    ) public onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];
        if (occasion.isDeleted) revert InvalidOccasionId(_occasionId);

        require(_date > block.timestamp, "Event date must be in the future");

        occasion._date = _date;
        occasion.maxTicketsPerUser = _maxTicketsPerUser;
        occasion.ticketModels[0].ticketType = _ipfsHash;
    }

    /**
     * @dev Update an existing occasion.
     * @param _occasionId ID of the occasion to update.
     * @param _ipfsHash New IPFS hash of occasion metadata.
     * @param _date New date for the occasion.
     */
    function updateOccasion(
        uint256 _occasionId,
        string calldata _ipfsHash,
        uint256 _date
    ) external onlyEventCreator(_occasionId) {
        updateOccasion(_occasionId, _ipfsHash, _date, 1);
    }

    

    /**
     * @dev Get all active occasions.
     */
    function getOccasions() external view returns (Occasion[] memory) {
        Occasion[] memory activeOccasions = new Occasion[](occasionIdCount);
        uint256 index;
        for (uint256 i = 0; i < occasionIdCount; i++) {
            if (occasions[i].isActive && !occasions[i].isDeleted) {
                activeOccasions[index] = occasions[i];
                index++;
            }
        }

        return activeOccasions;
    }

    /**
     * @dev Get a specific occasion by its ID.
     */
    function getOccasionById(uint256 _occasionId) external view returns (Occasion memory) {
        Occasion storage occasion = occasions[_occasionId];
        require(_occasionId <= occasionIdCount, "Invalid occasion ID");
        require(!occasion.isDeleted || occasion.isActive, "Occasion is either deleted or deactivated");
        return occasion;
    }

    /**
     * @dev Update a ticket model.
     * @param _occasionId ID of the occasion.
     * @param _modelId ID of the ticket model.
     * @param _ticketType New ticket type.
     * @param _price New ticket price.
     * @param _isTransferrable Whether the ticket is transferrable.
     * @param _isResellable Whether the ticket is resellable.
     * @param _isRefundable Whether the ticket is refundable.
     */
    function updateTicketModel(
        uint256 _occasionId,
        uint256 _modelId,
        string calldata _ticketType,
        uint256 _price,
        bool _isTransferrable,
        bool _isResellable,
        bool _isRefundable
    ) external onlyEventCreator(_occasionId) {
        TicketModel storage model = occasions[_occasionId].ticketModels[_modelId];
        require(model.isActive, "Ticket model is not active");

        model.ticketType = _ticketType;
        model.price = _price;
        model.isTransferrable = _isTransferrable;
        model.isResellable = _isResellable;
        model.isRefundable = _isRefundable;

        emit TicketModelUpdated(_occasionId, _modelId);
    }

    /**
     * @dev Deactivate a ticket model, making it unavailable for new ticket purchases.
     * @param _occasionId ID of the occasion.
     * @param _modelId ID of the ticket model to deactivate.
     */
    function deactivateTicketModel(uint256 _occasionId, uint256 _modelId) external onlyEventCreator(_occasionId) {
        TicketModel storage model = occasions[_occasionId].ticketModels[_modelId];
        require(model.isActive, "Ticket model is already inactive");

        model.isActive = false;

        emit TicketModelDeactivated(_occasionId, _modelId);
    }

    /**
     * @dev Delete a ticket model from an occasion.
     * @param _occasionId ID of the occasion.
     * @param _modelId ID of the ticket model to delete.
     */
    function deleteTicketModel(uint256 _occasionId, uint256 _modelId) external onlyEventCreator(_occasionId) {
        TicketModel storage model = occasions[_occasionId].ticketModels[_modelId];
        require(model.isActive, "Ticket model is inactive");

        delete occasions[_occasionId].ticketModels[_modelId];

        emit TicketModelDeleted(_occasionId, _modelId);
    }

    /**
     * @dev Deactivate an occasion.
     * @param _occasionId ID of the occasion to deactivate.
     */
    function deactivateOccasion(uint256 _occasionId) external onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];
        occasion.isActive = false;

        emit OccasionDeactivated(_occasionId);
    }

    /**
     * @dev Delete an occasion.
     * @param _occasionId ID of the occasion to delete.
     */
    function deleteOccasion(uint256 _occasionId) external onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];
        occasion.isDeleted = true;

        for (uint256 i = 0; i < totalMintedTickets; i++) {
            MintedTicket storage ticket = mintedTickets[i];
            if (ticket.occasionId == _occasionId) {
                _refundTicket(ticket._id);
            }
        }

        emit OccasionDeleted(_occasionId);
    }

    /**
     * @dev Add a ticket model to an occasion.
     * @param _occasionId ID of the occasion.
     * @param _ticketType Type of the ticket (e.g., VIP, General).
     * @param _price Price of the ticket.
     * @param _isTransferrable Whether the ticket is transferrable.
     * @param _isResellable Whether the ticket can be resold.
     * @param _totalTickets Number of tickets for this model.
     */
    function addTicketModel(
        uint256 _occasionId,
        string calldata _ticketType,
        uint256 _price,
        bool _isTransferrable,
        bool _isResellable,
        bool _isRefundable,
        uint256 _totalTickets
    ) external onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];
        TicketModel storage model = occasion.ticketModels.push();
        model.occasionId = _occasionId;
        model.ticketType = _ticketType;
        model.price = _price;
        model.isTransferrable = _isTransferrable;
        model.isResellable = _isResellable;
        model.isRefundable = _isRefundable;
        model.totalTickets = _totalTickets;
        model.isActive = true;
    }

    function _canMint() internal view virtual override returns (bool) {
        return true;
    }

    /**
 * @dev Mint a ticket from a specific model.
 * @param _occasionId ID of the occasion.
 * @param _modelId ID of the ticket model.
 */
function buyTicket(uint256 _occasionId, uint256 _modelId) external payable onlyActiveOccasion(_occasionId) nonReentrant {
    Occasion storage occasion = occasions[_occasionId];
    TicketModel storage ticketModel = occasion.ticketModels[_modelId];

    // Check if the ticket model is active and has available tickets
    require(ticketModel.soldTickets < ticketModel.totalTickets, "All available tickets have been sold");

    // Calculate the platform fee (2% of the ticket price)
    uint256 platformFee = (ticketModel.price * platformFeePercent).ceilDiv(100);

    // Calculate the total amount required (ticket price + platform fee)
    uint256 totalAmountRequired = ticketModel.price + platformFee;

    // Ensure the buyer has sent enough funds to cover both the ticket price and the platform fee
    require(msg.value >= totalAmountRequired, "Insufficient funds sent");

    // Transfer the platform fee to the platform owner
    (bool platformFeeSuccess,) = platformOwner.call{value: platformFee}("");
    require(platformFeeSuccess, "Platform fee transfer failed");

    // The remaining amount (ticket price) goes into the event's funds
    fundsByEventId[_occasionId] += ticketModel.price;

    // Mint the ticket (using ERC721's _safeMint method)
    _safeMint(msg.sender, 1);

    // Record the minted ticket's details
    MintedTicket storage mintedTicket = mintedTickets[_currentIndex];  // _currentIndex comes from ERC721Base
    mintedTicket._id = totalMintedTickets;
    mintedTicket.occasionId = _occasionId;
    mintedTicket.ticketModelId = _modelId;
    mintedTicket.owner = msg.sender;
    mintedTicket.price = ticketModel.price;
    mintedTicket.platformFee = platformFee;

    // Update the ticket count for the event and model
    ticketModel.soldTickets++;
    occasion.soldTickets++;

    emit TicketMinted(msg.sender, _occasionId, _modelId, ticketModel.price);

    // If the user sent more than the required amount, refund the excess
    if (msg.value > totalAmountRequired) {
        uint256 refundAmount = msg.value - totalAmountRequired;
        (bool refundSuccess,) = payable(msg.sender).call{value: refundAmount}("");
        require(refundSuccess, "Refund failed");
    }
}


    function transferTicket(uint256 _ticketId, address _recipient) external onlyTicketOwner(_ticketId) onlyExistingTicket(_ticketId) {
        MintedTicket storage ticket = mintedTickets[_ticketId];
        TicketModel storage ticketModel = occasions[ticket.occasionId].ticketModels[ticket.ticketModelId];

        require(ticketModel.isTransferrable, "Ticket is untransferrable");
        require(occasions[ticket.occasionId]._date > block.timestamp, "Ticket has expired");

        safeTransferFrom(msg.sender, _recipient, _ticketId);
        ticket.owner = _recipient;
    }

    function refundTicket(uint256 _ticketId) public onlyTicketOwner(_ticketId) onlyExistingTicket(_ticketId) nonReentrant {
        MintedTicket storage ticket = mintedTickets[_ticketId];
        TicketModel storage ticketModel = occasions[ticket.occasionId].ticketModels[ticket.ticketModelId];

        require(ticketModel.isRefundable, "Refund cannot be made");
        require(occasions[ticket.occasionId]._date >= block.timestamp, "Ticket has expired");

        (bool success,) = payable(msg.sender).call{value: ticket.price}("");
        require(success, "Insufficient funds");

        ticket.isBurnt = true;
        _burn(_ticketId, true);

    }

    function _refundTicket(uint256 _ticketId) private onlyExistingTicket(_ticketId) nonReentrant {
        MintedTicket storage ticket = mintedTickets[_ticketId];
        TicketModel storage ticketModel = occasions[ticket.occasionId].ticketModels[ticket.ticketModelId];

        require(ticketModel.isRefundable, "Refund cannot be made");
        require(occasions[ticket.occasionId]._date >= block.timestamp, "Ticket has expired");

        (bool success,) = payable(msg.sender).call{value: ticket.price}("");
        require(success, "Insufficient funds");

        ticket.isBurnt = true;
        _burn(_ticketId);

    }

    /**
     * @dev Check in a ticket.
     * @param _occasionId ID of the occasion.
     * @param _ticketId ID of the ticket.
     */
    function checkInTicket(uint256 _occasionId, uint256 _ticketId) external onlyEventCreator(_occasionId) onlyExistingTicket(_ticketId) {
        MintedTicket storage ticket = mintedTickets[_ticketId];
        require(ticket.occasionId == _occasionId, "Ticket does not belong to this occasion");
        require(!ticket.hasCheckedIn, "Ticket already checked in");
        require(!ticket.isBurnt, "Ticket has been burnt");

        ticket.hasCheckedIn = true;
        emit CheckedIn(_ticketId, _occasionId);
    }

    function getMintedTickets() external view returns (MintedTicket[] memory) {
        MintedTicket[] memory tickets = new MintedTicket[](_currentIndex);

        uint256 index;
        for(uint256 i = 0; i < _currentIndex; i++) {
            tickets[index] = mintedTickets[i];
        }

        return tickets;
    }
 
    function payoutToEventCreator(uint256 _occasionId) external nonReentrant {
        Occasion storage occasion = occasions[_occasionId];

        require(block.timestamp >= occasion._date + 1 days, "You can withdraw only after 24 hours");
        require(!occasion.isPaidOut, "Payout already completed");

        uint256 amount = fundsByEventId[_occasionId];
        fundsByEventId[_occasionId] = 0;
        occasion.isPaidOut = true;

        (bool success,) = payable(occasion.creator).call{value: amount}("");
        require(success, "Insufficient funds");

        emit EventFundsPaidOut(occasion.creator, amount);
    }
}
