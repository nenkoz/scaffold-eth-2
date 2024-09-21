// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract TravelToken is ERC20, Ownable {
    using Math for uint256;

    mapping(address => bool) public verifiedAddresses;
    uint256 public constant MAX_INITIAL_SUPPLY = 5000 * 10**18; // 5000 tokens with 18 decimals
    uint256 public constant MIN_INITIAL_SUPPLY = 1000 * 10**18; // 1000 tokens with 18 decimals
    uint256 public constant MAX_VERIFIED_USERS = 100;
    uint256 public verifiedUserCount;

    event AddressVerified(address indexed user, uint256 amount);

    constructor() ERC20("TravelToken", "TRVL") {}
    //TODO: add onlyOwner modifier
    function verifyAddress(address _user) public {
        require(!verifiedAddresses[_user], "Address already verified");
        require(verifiedUserCount < MAX_VERIFIED_USERS, "Maximum number of verified users reached");
        
        verifiedAddresses[_user] = true;
        verifiedUserCount++;
        
        uint256 amount = calculateInitialSupply(verifiedUserCount);
        _mint(_user, amount);
        
        emit AddressVerified(_user, amount);
    }
    
    function calculateInitialSupply(uint256 userNumber) internal pure returns (uint256) {
        // Linear decrease function
        uint256 totalDecrease = MAX_INITIAL_SUPPLY - MIN_INITIAL_SUPPLY;
        uint256 decreasePerUser = totalDecrease / (MAX_VERIFIED_USERS - 1);
        uint256 decrease = (userNumber - 1) * decreasePerUser;
        
        if (decrease > totalDecrease) {
            return MIN_INITIAL_SUPPLY;
        }
        
        return MAX_INITIAL_SUPPLY - decrease;
    }
    
    function verifyContractAddress(address _contract) external onlyOwner {
    verifyAddress(_contract);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(verifiedAddresses[_msgSender()] && verifiedAddresses[recipient], "Both addresses must be verified");
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        require(verifiedAddresses[sender] && verifiedAddresses[recipient], "Both addresses must be verified");
        return super.transferFrom(sender, recipient, amount);
    }

    // Optional: Function to mint additional tokens (if needed)
    function mint(address to, uint256 amount) external onlyOwner {
        require(verifiedAddresses[to], "Can only mint to verified addresses");
        _mint(to, amount);
    }
}