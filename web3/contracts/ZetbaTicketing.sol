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
    uint256 internal occasionIdCount;  // Global occasion counter
    address public platformOwner; // Address that collects the platform fee
    uint256 public platformFeePercent; // Platform fee in percentage (e.g., 2 means 2%)
    uint256 internal ticketsForSaleIdCount;
    


    // Event declarations
    event OccasionCreated(uint256 indexed _occasionId, address indexed _creator, string _ipfsHash);
    event TicketMinted(address indexed _owner, uint256 indexed _occasionId, uint256 _ticketModelId, uint256 _price);
    event CheckedIn(uint256 indexed _ticketId, uint256 _occasionId);
    event OccasionDeactivated(uint256 indexed _occasionId);
    event OccasionDeleted(uint256 indexed _occasionId);
    event TicketOfferedForSale(uint256 indexed _ticketId, address indexed _owner);
    event TicketResold(uint256 indexed _tickedId, address indexed _seller, address indexed _newOwner);
    event EventFundsPaidOut(address indexed _eventCreator, uint256 _amtPaidOut);

    constructor()
        ERC721Base(
            msg.sender,       // Contract admin
            "ZetbaTicket",    // Token name
            "ZKT",            // Token symbol
            msg.sender,       // Royalty recipient
            100               // Royalty points
        )
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender); // Grant the deployer the admin role
        platformOwner = msg.sender;
        platformFeePercent = 2;
    }

    struct MintedTicket {
        uint256 _id;
        address owner;
        uint256 occasionId;
        uint256 ticketModelId;
        string ticketType;
        string ipfsHash;
        uint256 price;
        uint256 platformFee;
        bool isBurnt;
        bool isForSale;
        bool hasCheckedIn;
    }

    struct TicketModel {
        uint256 occasionId;
        string ticketType;
        uint256 price;
        bool isTransferrable;
        bool isResellable;
        bool isRefundable;
        bool isActive;
        uint256 soldTickets;
        uint256 totalTickets;
    }

    struct Occasion {
        uint256 _id;
        address creator;
        string ipfsHash;
        uint256 _date;
        uint256 totalTickets;
        uint256 soldTickets;
        bool isActive;
        bool isDeleted;
        bool isPaidOut;
        uint256 maxTicketsPerUser;
        TicketModel[] ticketModels;
        uint256 ticketModelCount;
    }

    mapping(uint256 => Occasion) public occasions;   // Mapping for all occasions
    mapping(uint256 => MintedTicket) public mintedTickets; // Global mapping for all minted tickets
    mapping(address => uint256) public userToTickets;
    mapping(occasionId => uint256) public fundsByEventId;

    modifier onlyActiveOccasion(uint256 _occasionId) {
        require(occasions[_occasionId].isActive, "Occasion is not active");
        _;
    }

    modifier onlyEventCreator(uint256 _occasionId) {
        require(occasions[_occasionId].creator == msg.sender, "Caller is not the event creator");
        _;
    }

    modifier onlyTicketOwner(uint256 ticketId) {
        require(msg.sender == mintedTickets[ticketId].owner, "Caller is not the owner of the ticket");
        _;
    }

    /**
     * @dev Create a new occasion.
     * @param ipfsHash IPFS hash of occasion metadata.
     * @param date date of the occasion
     * @return _occasionId Newly created occasion's ID.
     */
    function createOccasion(
        string memory _ipfsHash,
        uint256 _date
    ) external returns (uint256 _occasionId) {
        require(date > block.timestamp, "Event date should be in the future");
        Occasion storage occasion = occasions[occasionIdCount];

        occasion._id = occasionIdCount;
        occasion.creator = msg.sender;
        occasion.ipfsHash = ipfsHash;
        occasion.date = date;
        occasion.isActive = true;
        occasion.isDeleted = false;

        occasionIdCount++; // Increment global occasion ID counter

        emit OccasionCreated(occasionIdCount, msg.sender, ipfsHash);
        return occasionIdCount - 1;
    }

    /**
     * @dev Update an existing occasion.
     * @param _occasionId ID of the occasion to update.
     * @param ipfsHash New IPFS hash of occasion metadata.
     * @param date New date for the occasion.
     */
    function updateOccasion(
        uint256 _occasionId,
        string memory _ipfsHash,
        uint256 _date
    ) external onlyEventCreator(_occasionId) {
        require(date > block.timestamp, "Event date should be in the future");
        Occasion storage occasion = occasions[_occasionId];

        require(!occasion.isDeleted, "Occasion has been deleted");

        occasion.ipfsHash = ipfsHash;
        occasion.date = date;
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
    function getOccasion(uint256 _occasionId) external view returns (Occasion memory) {
        Occasion storage occasion = occasions[_occasionId];
        require(_occasionId <= occasionIdCount, "Invalid occasion ID");
        require(!occasion.isDeleted || occasion.isActive, "Occasion is either deleted or deactivate");
        return occasion;
    }

    /**
     * @dev Deactivate an occasion.
     * @param _occasionId ID of the occasion to deactivate.
     */
    function deactivateOccasion(uint256 _occasionId) external onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];
        occasion.isActive = false;  // Deactivate instead of deleting to avoid inconsistencies
        
        emit OccasionDeactivated(_occasionId);
    }


    /**
     * @dev Delete an occasion.
     * @param _occasionId ID of the occasion to delete.
     */
    function deleteOccasion(uint256 _occasionId) external onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];

        occasion.isDeleted = true;  // Deactivate instead of deleting to avoid inconsistencies

        for(uint256 i = 0; i < _currentIndex; i++) {
            MintedTicket storage ticket = mintedTickets[i];
            if(ticket.occasionId == _occasionId) {
                _refundTicket(ticket._id);
            }
        }
        
        emit OccasionDeleted(_occasionId);
    }

    /**
     * @dev Add a ticket model to an occasion.
     * @param _occasionId ID of the occasion.
     * @param ticketType Type of the ticket (e.g., VIP, General).
     * @param price Price of the ticket.
     * @param isTransferrable Whether the ticket is transferrable.
     * @param isResellable Whether the ticket can be resold.
     * @param totalTickets Number of tickets for this model.
     */
    function addTicketModel(
        uint256 _occasionId,
        string memory _ticketType,
        uint256 _price,
        bool _isTransferrable,
        bool _isResellable,
        bool _isRefundable,
        uint256 _totalTickets
    ) external onlyEventCreator(_occasionId) {
        Occasion storage occasion = occasions[_occasionId];
        uint256 modelId = occasion.ticketModelCount;

        occasion.ticketModels[modelId] = TicketModel({
            occasionId: _occasionId,
            ticketType: _ticketType,
            price: _price,
            isTransferrable: _isTransferrable,
            isResellable: _isResellable,
            isRefundable: _isRefundable,
            totalTickets: _totalTickets,
            soldTickets: 0,
            isActive: true
        });
    }

    /// @dev Returns whether a token can be minted in the given execution context.
    function _canMint() internal view virtual override returns (bool) {
        return true;
    }

    /**
     * @dev Mint a ticket from a specific model.
     * @param _occasionId ID of the occasion.
     * @param modelId ID of the ticket model.
     */
    function buyTicket(
        uint256 _occasionId,
        uint256 _modelId
    ) external payable onlyActiveOccasion(_occasionId) nonReentrant {
        Occasion storage occasion = occasions[_occasionId];
        TicketModel storage ticketModel = occasion.ticketModels[_modelId];
        uint256 maxTicketsPerUser = occasion.maxTicketsPerUser;

        require(occasion.isActive, "Ticket can be bought for deactivated event");
        require(!occasion.isDeleted, "Event is deleted");
        require(ticketModel.soldTickets < ticketModel.totalTickets, "All tickets sold");
        require(userToTickets[msg.sender] < occasion.maxTicketsPerUser, "Exceeded ticket limit for user");

        // Calculate the platform fee (percentage of the ticket price)
        uint256 platformFee = (ticketModel.price * platformFeePercent) / 100;

        require(msg.value >= ticketModel.price + platformFee, "Insufficient payment");
        
        // Amount to be sent to the event creator
        uint256 creatorAmount = ticketModel.price - platformFee;

        // Transfer the platform fee to the platform owner
        (bool platformFeeSent, ) = platformOwner.call{value: platformFee * 2}("");
        require(platformFeeSent, "Platform fee transfer failed");

        // Keep record of the remaining amount on the smart contract
        fundsByEventId[_occasionId] += creatorAmount;

        // Refund any excess payment
        if (msg.value > ticketModel.price + platformFee) {
            payable(msg.sender).transfer(msg.value - (ticketModel.price + platformFee));
        }

        if(platformFeeSent && fundsByEventId[_occasionId]) {
        string memory ticketURI = tokenURI(_currentIndex);
        mintTo(msg.sender, ticketURI);

        mintedTickets[_currentIndex] = MintedTicket({
            _id: _currentIndex,
            owner: msg.sender,
            occasionId: _occasionId,
            ticketModelId: _modelId,
            ticketType: ticketModel.ticketType,
            ipfsHash: "",
            price: ticketModel.price,
            platformFee: platformFee,
            isBurnt: false,
            isForSale: false,
            hasCheckedIn: false
        });

        // Update sold ticket count for the event
        ticketModel.soldTickets += 1;
        occasion.soldTickets += 1;
        emit TicketMinted(msg.sender, _occasionId, _modelId, ticketModel.price);
        }
    }

    function transferTicket(
        uint256 _ticketId,
        address _recipient
    ) external {
        MintedTicket transferredTicket = mintedTickets[_ticketId];
        TicketModel storage ticketModel = occasion.ticketModels[transferredTicket .ticketModelId];
        bool transferrable = ticketModel.isTransferrable;

        require(occasion._date > block.timestamp, "Ticket has expired");
        require(transferrable, "Ticket cannot be transferred");

        if(transferrable) {
            transferredTicket.owner = _recipient;
            _transfer(msg.sender, _recipient, _ticketId);
        }
    }

    function offerTicketForSale(_ticketId) external onlyTicketOwner(_ticketId) {
        MintedTicket storage tikcet = mintedTickets[_ticketId];
        TicketModel storage ticketModel = occasion.ticketModels[transferredTicket .ticketModelId];
        bool resellable = ticketModel.isResellable;

        require(resellable, "Ticket cannot be sold");

        if(resellable){
            tikcet.isForSale = true;
            emit TicketOfferedForSale(_ticketId, msg.sender);
        }
    }

    function getTicketsForSale() external view returns (MintedTicket[] memory) {
        MintedTicket[] memory ticketsForSale = new Occasion[](ticketsForSaleIdCount);

        for(uint256 i = 0; i < ticketsForSaleIdCount; i++) {
            MintedTicket storage ticket = mintedTickets[i];
            if(ticket.isForSale) {
                ticketsForSale[i] = ticket;
            }
        }

        return ticketsForSale;
    }

    function resellTicket(
        uint256 _ticketId
    ) external payable nonReentrant {
        MintedTicket resoldTicket = mintedTickets[_ticketId];
        TicketModel storage ticketModel = occasion.ticketModels[resoldTicket.ticketModelId];
        bool resellable = ticketModel.isResellable;
        address prevOwner = resoldTicket.owner;

        require(resellable, "Ticket cannot be transferred");
        require(occasion._date > block.timestamp, "Ticket has expired");

        // Calculate the platform fee (percentage of the ticket price)
        uint256 platformFee = (ticketModel.price * platformFeePercent) / 100;
        require(msg.value >= ticketModel.price + platformFee, "Insufficient payment");
        
        // Amount to be sent to the event creator
        uint256 sellerAmt = msg.value - platformFee;

        // Transfer the platform fee to the platform owner
        (bool platformFeeSent, ) = platformOwner.call{value: platformFee}("");
        require(platformFeeSent, "Platform fee transfer failed");

        (bool sellerFeeSent, ) = prevOwner.call{value: sellerAmt}("");
        require(platformFeeSent, "Platform fee transfer failed");


        if(platformFeeSent && sellerFeeSent) {
            resoldTicket.owner = msg.sender;
            _transfer(resoldTicket.owner, msg.sender, _ticketId);
            emit TicketResold(_ticketId, prevOwner, msg.sender)
        }


    }

    /**
 * @dev Refunds a user who purchased a ticket.
 * @param _ticketId ID of the ticket to be refunded.
 */
function refundTicket(uint256 _ticketId) external payable onlyTicketOwner(_ticketId) nonReentrant {
    // Check if the ticket exists and is owned by the caller
    MintedTicket storage ticket = mintedTickets[_ticketId];
    require(!ticket.isBurnt, "Ticket has already been burnt");
    require(!ticket.hasCheckedIn, "Cannot refund after check-in");

    // Get the ticket model and check if it's refundable
    Occasion storage occasion = occasions[ticket.occasionId];
    TicketModel storage ticketModel = occasion.ticketModels[ticket.ticketModelId];
    require(ticketModel.isRefundable, "This ticket is not refundable");
    require(occasion._date > block.timestamp, "Ticket has expired");

    // Calculate the refund amount
    uint256 refundAmount = ticket.price;
    
    // Transfer the refund to the buyer (caller)
    (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
    require(success, "Refund transfer failed");

    if(success) {
        // Burn the ticket (mark it as burnt so it can't be used)
        _burn(_ticketId);
        ticket.isBurnt = true;

        // Update sold tickets count (optional)
        ticketModel.soldTickets -= 1;

        // Emit an event for the refund
        emit TicketRefunded(msg.sender, _ticketId, refundAmount);
    }
}

    /**
 * @dev Refunds a user who purchased a ticket.
 * @param _ticketId ID of the ticket to be refunded.
 */
function _refundTicket(uint256 _ticketId) external payable nonReentrant {
    // Check if the ticket exists and is owned by the caller
    MintedTicket storage ticket = mintedTickets[_ticketId];
    require(!ticket.isBurnt, "Ticket has already been burnt");
    require(!ticket.hasCheckedIn, "Cannot refund after check-in");

    // Get the ticket model and check if it's refundable
    Occasion storage occasion = occasions[ticket.occasionId];
    TicketModel storage ticketModel = occasion.ticketModels[ticket.ticketModelId];
    require(occasion._date > block.timestamp, "Ticket has expired");

    // Calculate the refund amount
    uint256 refundAmount = ticket.price;
    
    // Transfer the refund to the buyer (caller)
    (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
    require(success, "Refund transfer failed");

    if(success) {
        // Burn the ticket (mark it as burnt so it can't be used)
        _burn(_ticketId);
        ticket.isBurnt = true;

        // Update sold tickets count (optional)
        ticketModel.soldTickets -= 1;

        // Emit an event for the refund
        emit TicketRefunded(msg.sender, _ticketId, refundAmount);
    }
}


    /**
     * @dev Check in a ticket.
     * @param _occasionId ID of the occasion.
     * @param ticketId ID of the ticket.
     */
    function checkInTicket(uint256 _occasionId, uint256 _ticketId) external onlyEventCreator(_occasionId) {
        MintedTicket storage ticket = mintedTickets[_ticketId];
        require(ticket._occasionId == _occasionId, "Ticket does not belong to this occasion");
        require(!ticket.hasCheckedIn, "Ticket already checked in");
        require(!ticket.isBurnt, "Ticket has been burnt");

        ticket.hasCheckedIn = true;
        emit CheckedIn(_ticketId, _occasionId);
    }

    function payoutToEventCreator(uint256 _occasionId) external {
        Occasion storage occasion = occasions[_occasionId];
        require(!occasion.isPaidOut, "Payout already done");
        require(block.timestamp > occasion.date, "You only get funds after event");
        require(block.timestamp >= occasion.date + 86400000, "You have to wait 24 hours after the event date before you get payout");

        uint256 amount = fundsByEventId[_occasionId];
        fundsByEventId[_occasionId] = 0;
        occasion.isPaidOut = true;

        // Transfer the total funds to the event creator
        occasion.creator.transfer(amount);
        emit EventFundsPaidOut(occasion.creator, amount);
    }
}
