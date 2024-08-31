// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


// since the keyword Event is reserved in solidity, we use EventOccasion instead
contract EventOccasion is ERC721 {

    public owner address;
    public totalOccasions uint;
    public totalTickets uint;


    constructor() {
        ERC721("EventOccasion", "EVO");
        owner = msg.sender;

    }

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not allowed to perform this action");
        _;
    }


    struct Occasion {
        string name;
        string description;
        string location;
        uint date;
        uint ticketPrice;
        uint totalTickets;
        uint soldTickets;
        bool isActive;
        address creator;
    }


    mapping (uint => Occasion) public  occasions;
    
    // create an occasion
    function createOccasion(
        string memory _name,
        string memory _description, 
        string memory _location, 
        uint _date, 
        uint _ticketPrice, 
        uint _totalTickets 

        ) public returns (uint) {
        require(bytes(_name).length > 0, "Name is required");
        require(bytes(_description).length > 0, "Description is required");
        require(bytes(_location).length > 0, "Location is required");
        require(_date > 0, "Date is required");
        require(_ticketPrice > 0, "Ticket price must be greater than 0");
        require(_totalTickets > 0, "Total tickets must be greater than 0");

        
        // increase the totalOccasions by 1
        uint _id = totalOccasions++;

        // create a new occasion
        Occasion memory newOccasion = Occasion(
            _name, 
            _description,
             _location, 
             _date,
              _ticketPrice, 
              _totalTickets, 
              0, 
              true.
              msg.sender
              );

        occasions[_id] = newOccasion;
        return _id;
    }

    //get all an occasion
    function getOccasion(uint _id) public view returns (Occasion memory) {
        // check if the occasion exists
        require(occasions[_id].isActive, "Occasion does not exist");

        return occasions[_id];
    }


    // update an occasion
    function updateOccasion(
        uint _id,
        string memory _name,
        string memory _description, 
        string memory _location, 
        uint _date, 
        uint _ticketPrice, 
        uint _totalTickets 

        ) public returns (uint) {

        // check if the occasion exists
        require(occasions[_id].isActive, "Occasion does not exist");

        // check if the sender is the creator of the occasion
        require(occasions[_id].creator == msg.sender, "You are not the owner of this occasion");

        // check that all the required fields are provided
        require(bytes(_name).length > 0, "Name is required");
        require(bytes(_description).length > 0, "Description is required");
        require(bytes(_location).length > 0, "Location is required");
        require(_date > 0, "Date is required");
        require(_ticketPrice > 0, "Ticket price must be greater than 0");
        require(_totalTickets > 0, "Total tickets must be greater than 0");
        
        // create a new occasion
        Occasion memory newOccasion = Occasion(
            _name, 
            _description,
             _location, 
             _date,
              _ticketPrice, 
              _totalTickets, 
              0, 
              true.
              msg.sender
              );

        occasions[_id] = newOccasion;
        return _id;
    }

    // delete an occasion
    function deleteOccasion(uint _id) public onlyOwner {
        delete occasions[_id];
    }


    // buy a ticket
    function buyTicket(uint _id) public payable {
        // check if the occasion exists
        require(occasions[_id].isActive, "Occasion does not exist");

        // check if the occasion is active
        require(occasions[_id].isActive, "Occasion is not active");

        // check if the ticket price is greater than the amount sent
        require(msg.value >= occasions[_id].ticketPrice, "Insufficient funds");

        // check if there are available tickets
        require(occasions[_id].soldTickets < occasions[_id].totalTickets, "No more tickets available");

        // transfer the ticket price to the owner
        owner.transfer(occasions[_id].ticketPrice);

        // increase the sold tickets by 1
        occasions[_id].soldTickets++;

        totalTickets++;

        // mint a new token
        _mint(msg.sender, totalTickets);
    }

    
}