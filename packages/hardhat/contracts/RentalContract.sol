// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TokenContract.sol";
import "hardhat/console.sol";

contract RentalContract is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _propertyIds;
    Counters.Counter private _bookingIds;

    uint256 public totalListedProperties;
    uint256 public totalBookings;

    TravelToken public travelToken;

    struct Property {
        uint256 id;
        address owner;
        uint256 pricePerNight;
        mapping(uint256 => uint256) availabilityBitmap;
    }

    struct Booking {
        uint256 id;
        uint256 propertyId;
        uint256 startTimestamp;
        uint256 endTimestamp;
        address renter;
        BookingStatus status;
        uint256 totalPrice;
    }

    enum BookingStatus { Pending, PreApproved, Confirmed, Completed, Cancelled }

    mapping(uint256 => Property) public properties;
    mapping(uint256 => Booking) public bookings;
    mapping(uint256 => uint256[]) public propertyBookings;
    mapping(address => uint256[]) public userProperties;

    event PropertyListed(uint256 indexed propertyId, address indexed owner, uint256 pricePerNight);
    event BookingRequested(uint256 indexed bookingId, uint256 indexed propertyId, address indexed renter, uint256 startTimestamp, uint256 endTimestamp);
    event BookingStatusUpdated(uint256 indexed bookingId, BookingStatus status);
    event AvailabilityUpdated(uint256 indexed propertyId, uint256 startTimestamp, uint256 endTimestamp, bool isAvailable);

    constructor(address _travelTokenAddress) {
        travelToken = TravelToken(_travelTokenAddress);
    }

    function listProperty(uint256 _pricePerNight) external returns (uint256) {
        _propertyIds.increment();
        uint256 newPropertyId = _propertyIds.current();

        Property storage newProperty = properties[newPropertyId];
        newProperty.id = newPropertyId;
        newProperty.owner = msg.sender;
        newProperty.pricePerNight = _pricePerNight;

        // Set all days as unavailable initially
        for (uint256 i = 0; i < 16; i++) {
            newProperty.availabilityBitmap[i] = 0;
        }

        userProperties[msg.sender].push(newPropertyId);

        totalListedProperties++;

        emit PropertyListed(newPropertyId, msg.sender, _pricePerNight);

        return newPropertyId;
    }

    function getMyProperties() external view returns (uint256[] memory) {
        return userProperties[msg.sender];
    }

    function setAvailability(uint256 _propertyId, uint256 _startTimestamp, uint256 _endTimestamp, bool _isAvailable) public {
        require(_startTimestamp < _endTimestamp, "Invalid date range");
        Property storage property = properties[_propertyId];
        require(msg.sender == property.owner, "Only property owner can set availability");

        for (uint256 timestamp = _startTimestamp; timestamp < _endTimestamp; timestamp += 1 days) {
            uint256 dayIndex = (timestamp / 1 days) % 256;
            uint256 slotIndex = (timestamp / 1 days) / 256;
            uint256 bitMask = 1 << dayIndex;
            
            if (_isAvailable) {
                property.availabilityBitmap[slotIndex] |= bitMask;
            } else {
                property.availabilityBitmap[slotIndex] &= ~bitMask;
            }
        }

        emit AvailabilityUpdated(_propertyId, _startTimestamp, _endTimestamp, _isAvailable);
    }

    function isAvailable(uint256 _propertyId, uint256 _timestamp) public view returns (bool) {
        Property storage property = properties[_propertyId];
        uint256 dayIndex = (_timestamp / 1 days) % 256;
        uint256 slotIndex = (_timestamp / 1 days) / 256;
        uint256 bitMask = 1 << dayIndex;
        return (property.availabilityBitmap[slotIndex] & bitMask) != 0;
    }

    function getAvailabilityRange(uint256 _propertyId, uint256 _startTimestamp, uint256 _endTimestamp) 
    external 
    view 
    returns (bool[] memory) 
    {
        require(_startTimestamp < _endTimestamp, "Invalid date range");
        
        uint256 rangeLength = (_endTimestamp - _startTimestamp) / 1 days;
        bool[] memory availabilityRange = new bool[](rangeLength);
        
        for (uint256 i = 0; i < rangeLength; i++) {
            availabilityRange[i] = isAvailable(_propertyId, _startTimestamp + (i * 1 days));
        }
        
        return availabilityRange;
    }

    function calculateTotalCost(uint256 _propertyId, uint256 _startTimestamp, uint256 _endTimestamp) public view returns (uint256) {
        Property storage property = properties[_propertyId];
        uint256 numberOfNights = (_endTimestamp - _startTimestamp) / 1 days;
        return property.pricePerNight * numberOfNights;
    }

    function requestBooking(uint256 _propertyId, uint256 _startTimestamp, uint256 _endTimestamp) external nonReentrant {
        require(_startTimestamp < _endTimestamp, "Invalid date range");
        
        Property storage property = properties[_propertyId];
        require(property.owner != address(0), "Property does not exist");
        require(property.owner != msg.sender, "Owner cannot book their own property");
        
        for (uint256 timestamp = _startTimestamp; timestamp < _endTimestamp; timestamp += 1 days) {
            require(isAvailable(_propertyId, timestamp), "Property not available for the entire duration");
        }

        uint256 totalCost = calculateTotalCost(_propertyId, _startTimestamp, _endTimestamp);

        _bookingIds.increment();
        uint256 newBookingId = _bookingIds.current();

        bookings[newBookingId] = Booking({
            id: newBookingId,
            propertyId: _propertyId,
            startTimestamp: _startTimestamp,
            endTimestamp: _endTimestamp,
            renter: msg.sender,
            status: BookingStatus.Pending,
            totalPrice: totalCost
        });

        propertyBookings[_propertyId].push(newBookingId);

        totalBookings++;

        emit BookingRequested(newBookingId, _propertyId, msg.sender, _startTimestamp, _endTimestamp);
    }

    function preApproveBooking(uint256 _bookingId) external nonReentrant {
        Booking storage booking = bookings[_bookingId];
        Property storage property = properties[booking.propertyId];
        require(msg.sender == property.owner, "Only property owner can pre-approve");
        require(booking.status == BookingStatus.Pending, "Booking not pending");
        
        booking.status = BookingStatus.PreApproved;
        emit BookingStatusUpdated(_bookingId, BookingStatus.PreApproved);
    }

    function completeBooking(uint256 _bookingId) external nonReentrant {
        Booking storage booking = bookings[_bookingId];
        Property storage property = properties[booking.propertyId];
        require(booking.status == BookingStatus.Confirmed, "Booking not confirmed");
        require(block.timestamp >= booking.endTimestamp, "Booking not yet completed");
        
        require(travelToken.transfer(property.owner, booking.totalPrice), "Token transfer to owner failed");
        
        booking.status = BookingStatus.Completed;
        emit BookingStatusUpdated(_bookingId, BookingStatus.Completed);
    }

    function cancelBooking(uint256 _bookingId) external {
        Booking storage booking = bookings[_bookingId];
        require(msg.sender == booking.renter || msg.sender == properties[booking.propertyId].owner, "Only renter or property owner can cancel the booking");
        require(booking.status == BookingStatus.Pending || booking.status == BookingStatus.PreApproved, "Can only cancel pending or pre-approved bookings");

        booking.status = BookingStatus.Cancelled;
        emit BookingStatusUpdated(_bookingId, BookingStatus.Cancelled);

        if (booking.status == BookingStatus.PreApproved) {
            for (uint256 timestamp = booking.startTimestamp; timestamp < booking.endTimestamp; timestamp += 1 days) {
                setAvailability(booking.propertyId, timestamp, timestamp + 1 days, true);
            }
        }
    }

    function getAvailableProperties(uint256 _startTimestamp, uint256 _endTimestamp, uint256 _maxPricePerNight) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(_startTimestamp < _endTimestamp, "Invalid date range");

        uint256[] memory availableProperties = new uint256[](_propertyIds.current());
        uint256 count = 0;

        for (uint256 i = 1; i <= _propertyIds.current(); i++) {
            Property storage property = properties[i];
            if (property.pricePerNight <= _maxPricePerNight) {
                bool isPropertyAvailable = true;
                for (uint256 timestamp = _startTimestamp; timestamp < _endTimestamp; timestamp += 1 days) {
                    if (!isAvailable(i, timestamp)) {
                        isPropertyAvailable = false;
                        break;
                    }
                }
                if (isPropertyAvailable) {
                    availableProperties[count] = i;
                    count++;
                }
            }
        }

        // Resize the array to remove empty slots
        assembly {
            mstore(availableProperties, count)
        }

        return availableProperties;
    }

    function getPropertyBookings(uint256 _propertyId, bool _onlyPendingAndPreApproved) external view returns (uint256[] memory) {
        uint256[] memory allBookings = propertyBookings[_propertyId];
        uint256[] memory filteredBookings = new uint256[](allBookings.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allBookings.length; i++) {
            Booking storage booking = bookings[allBookings[i]];
            if (!_onlyPendingAndPreApproved || 
                (booking.status == BookingStatus.Pending || booking.status == BookingStatus.PreApproved)) {
                filteredBookings[count] = booking.id;
                count++;
            }
        }

        // Resize the array to remove empty slots
        assembly {
            mstore(filteredBookings, count)
        }

        return filteredBookings;
    }

function approveAndConfirmBooking(uint256 _bookingId) external nonReentrant {
    Booking storage booking = bookings[_bookingId];
    require(msg.sender == booking.renter, "Only renter can confirm");
    require(booking.status == BookingStatus.PreApproved, "Booking not pre-approved");
    
    uint256 currentAllowance = travelToken.allowance(msg.sender, address(this));
    require(currentAllowance >= booking.totalPrice, "Insufficient allowance. Please approve tokens first.");
    
    require(travelToken.transferFrom(msg.sender, address(this), booking.totalPrice), "Token transfer failed");
    
    booking.status = BookingStatus.Confirmed;
    emit BookingStatusUpdated(_bookingId, BookingStatus.Confirmed);
}
}
