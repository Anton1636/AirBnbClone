// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract DappAirBnb is Ownable, ReentrancyGuard {
  using Counters for Counters.Counter;
  Counters.Counter private _totalAppartments;

  struct ApartmentStruct {
    uint id;
    string name;
    string description;
    string location;
    string images;
    uint rooms;
    uint price;
    address owner;
    bool booked;
    bool deleted;
    uint timestamp;
  }

  struct BookingStruct {
    uint id;
    uint aid;
    address tenant;
    uint date;
    uint price;
    bool checked;
    bool cancelled;
  }

  struct ReviewStruct {
    uint id;
    uint aid;
    string reviewtext;
    uint timestamp;
    address owner;
  }

  uint public securityFee;
  uint public taxPercent;

  mapping(uint => ApartmentStruct) apartments;
  mapping(uint => BookingStruct[]) bookingsOf;
  mapping(uint => ReviewStruct[]) reviewOf;
  mapping(uint => bool) appartmentExist;
  mapping(uint => uint[]) bookedDates;
  mapping(uint => mapping(uint => bool)) isDateBooked;
  mapping(address => mapping(uint => bool)) hasBooked;

  constructor(uint _taxPercent, uint _securityFee) {
    taxPercent = _taxPercent;
    securityFee = _securityFee;
  }

  function createAppartment(
    string memory name,
    string memory description,
    string memory location,
    string memory images,
    uint rooms,
    uint price
  ) public {
    require(bytes(name).length > 0, 'Name cannot be empty');
    require(bytes(description).length > 0, 'Description cannot be empty');
    require(bytes(location).length > 0, 'Location cannot be empty');
    require(bytes(images).length > 0, 'Images cannot be empty');
    require(rooms > 0, 'Rooms cannot be empty');
    require(price > 0 ether, 'Price cannot be empty');

    _totalAppartments.increment();
    ApartmentStruct memory apartment;

    apartment.id = _totalAppartments.current();
    apartment.name = name;
    apartment.description = description;
    apartment.location = location;
    apartment.images = images;
    apartment.rooms = rooms;
    apartment.price = price;
    apartment.owner = msg.sender;
    apartment.timestamp = currentTime();

    appartmentExist[apartment.id] = true;
    apartments[apartment.id] = apartment;
  }

  function updateAppartment(
    uint id,
    string memory name,
    string memory description,
    string memory location,
    string memory images,
    uint rooms,
    uint price
  ) public {
    require(appartmentExist[id], 'Apartment not found');
    require(msg.sender == apartments[id].owner, 'Unauthorized entity');
    require(bytes(name).length > 0, 'Name cannot be empty');
    require(bytes(description).length > 0, 'Description cannot be empty');
    require(bytes(location).length > 0, 'Location cannot be empty');
    require(bytes(images).length > 0, 'Images cannot be empty');
    require(rooms > 0, 'Rooms cannot be empty');
    require(price > 0 ether, 'Price cannot be empty');

    ApartmentStruct memory apartment = apartments[id];

    apartment.name = name;
    apartment.description = description;
    apartment.location = location;
    apartment.images = images;
    apartment.rooms = rooms;
    apartment.price = price;

    apartments[apartment.id] = apartment;
  }

  function deleteAppartment(uint id) public {
    require(appartmentExist[id], 'Apartment not found');
    require(msg.sender == apartments[id].owner, 'Unauthorized entity');

    appartmentExist[id] = false;
    apartments[id].deleted = true;
  }

  function getApartment(uint id) public view returns (ApartmentStruct memory) {
    return apartments[id];
  }

  function getApartments() public view returns (ApartmentStruct[] memory Apartments) {
    uint256 available;

    for (uint i = 1; i <= _totalAppartments.current(); i++) {
      if (!apartments[i].deleted) available++;
    }

    Apartments = new ApartmentStruct[](available);

    uint256 index;

    for (uint i = 1; i <= _totalAppartments.current(); i++) {
      if (!apartments[i].deleted) {
        Apartments[index++] = apartments[i];
      }
    }
  }

  function bookApartment(uint aid, uint[] memory dates) public payable {
    uint totalPrice = apartments[aid].price * dates.length;
    uint totalSecurityFee = (totalPrice * securityFee) / 100;

    require(appartmentExist[aid], 'Apartment not found!');
    require(msg.value >= (totalPrice + totalSecurityFee), 'Insufficient fund!');
    require(datesCleared(aid, dates), 'One or more dates not available');

    for (uint i = 0; i < dates.length; i++) {
      BookingStruct memory booking;
      booking.id = bookingsOf[aid].length;
      booking.aid = aid;
      booking.tenant = msg.sender;
      booking.date = dates[i];
      booking.price = apartments[aid].price;

      bookingsOf[aid].push(booking);
      bookedDates[aid].push(dates[i]);
      isDateBooked[aid][dates[i]] = true;
    }
  }

  function checkInApartment(uint aid, uint bookingId) public nonReentrant {
    BookingStruct memory booking = bookingsOf[aid][bookingId];

    require(msg.sender == booking.tenant, 'Unauthorized entity');
    require(!booking.checked, 'Double chekcing not allowed');

    bookingsOf[aid][bookingId].checked = true;
    hasBooked[msg.sender][aid] = true;

    uint tax = (booking.price * taxPercent) / 100;
    uint fee = (booking.price * securityFee) / 100;

    payTo(apartments[aid].owner, booking.price - tax);
    payTo(owner(), tax);
    payTo(booking.tenant, fee);
  }

  function refoundBooking(uint aid, uint bookingId) public nonReentrant {
    BookingStruct memory booking = bookingsOf[aid][bookingId];
    require(!booking.checked, 'Apartment already checked on this date!');
    require(isDateBooked[aid][booking.date], 'Did not book on this date!');

    if (msg.sender != owner()) {
      require(msg.sender == booking.tenant, 'Unauthorized tenant!');
      require(booking.date > currentTime(), 'Can no longer refund, booking date started');
    }

    bookingsOf[aid][bookingId].cancelled = true;
    isDateBooked[aid][booking.date] = false;

    uint lastIndex = bookedDates[aid].length - 1;
    uint lastBookingId = bookedDates[aid][lastIndex];
    bookedDates[aid][bookingId] = lastBookingId;
    bookedDates[aid].pop();

    uint fee = (booking.price * securityFee) / 100;
    uint collateral = fee / 2;

    payTo(apartments[aid].owner, collateral);
    payTo(owner(), collateral);
    payTo(msg.sender, booking.price);
  }

  function claimFunds(uint aid, uint bookingId) public nonReentrant {
    BookingStruct memory booking = bookingsOf[aid][bookingId];

    require(msg.sender == apartments[aid].owner || msg.sender == owner(), 'Unauthorized entity');
    require(!booking.checked, 'Already checked in');
    require(booking.date < currentTime(), 'Not allowed, booking date not exceeded');

    uint tax = (booking.price * taxPercent) / 100;
    uint fee = (booking.price * securityFee) / 100;

    payTo(apartments[aid].owner, booking.price - tax);
    payTo(owner(), tax);
    payTo(booking.tenant, fee);
  }

  function datesCleared(uint aid, uint[] memory dates) internal view returns (bool) {
    bool dateNotUsed = true;

    for (uint i = 0; i < dates.length; i++) {
      for (uint j = 0; j < bookedDates[aid].length; j++) {
        if (dates[i] == bookedDates[aid][j]) {
          dateNotUsed = false;
        }
      }
    }

    return dateNotUsed;
  }

  function getBooking(uint aid, uint bookingId) public view returns (BookingStruct memory) {
    return bookingsOf[aid][bookingId];
  }

  function getBookings(uint aid) public view returns (BookingStruct[] memory) {
    return bookingsOf[aid];
  }

  function getUnavailableDates(uint aid) public view returns (uint[] memory) {
    return bookedDates[aid];
  }

  function addReview(uint aid, string memory comment) public {
    require(appartmentExist[aid], 'Appartment not available');
    require(hasBooked[msg.sender][aid], 'Book first before review');
    require(bytes(comment).length > 0, 'Comment cannot be empty');

    ReviewStruct memory review;
    review.id = reviewOf[aid].length;
    review.aid = aid;
    review.reviewtext = comment;
    review.owner = msg.sender;
    review.timestamp = currentTime();

    reviewOf[aid].push(review);
  }

  function getReviews(uint aid) public view returns (ReviewStruct[] memory) {
    return reviewOf[aid];
  }

  function getQualifiedReviewers(uint aid) public view returns (address[] memory Tenants) {
    uint256 available;

    for (uint i = 0; i < bookingsOf[aid].length; i++) {
      if (bookingsOf[aid][i].checked) available++;
    }

    Tenants = new address[](available);

    uint256 index;

    for (uint i = 0; i < bookingsOf[aid].length; i++) {
      if (bookingsOf[aid][i].checked) {
        Tenants[index++] = bookingsOf[aid][i].tenant;
      }
    }
  }

  function tenantBooked(uint aid) public view returns (bool) {
    return hasBooked[msg.sender][aid];
  }

  function currentTime() internal view returns (uint256) {
    return (block.timestamp * 1000) + 1000;
  }

  function payTo(address to, uint256 amount) internal {
    (bool success, ) = payable(to).call{ value: amount }('');
    require(success);
  }
}
