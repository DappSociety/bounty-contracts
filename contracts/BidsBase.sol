pragma solidity ^0.4.19;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "./utils/ArrayAddress.sol";
import "./utils/Helpers.sol";
import "./Bounties.sol";

/**
 * @title Bids
 * @dev Tightly-coupled to Bounties. Handles all submissions and payouts.
 */
contract BidsBase is Ownable, Helpers {
  using ArrayAddress for address[];
  using SafeMath for uint256;

  /* Events */
  event BidOwnerChanged(uint256 bounty, uint256 bid,  address to);
  event BidDataChanged(uint256 bounty, uint256 bid, string data);
  event BidSharesUpdated(uint256 bounty, uint256 bid, address who, uint256 shares);
  event BountiesContractChanged(address to);

  /* Data Structure */
  enum BidStatus { Active, Withdrawn, Rejected, Accepted }
  struct Bid {
    address owner; // has all permissions on the bid (human or contract)
    string data; // IPFS hash to json file
    BidStatus status; // current bid status
    uint256 bountyId; // link to bounties[] in Bounties contract
    uint256 amountPaid; // how much this bid has been paid
    uint256 membersPointer; // pointer for members array
    address[] members; // all current members of the bid
    mapping (address => uint) shares; // weighted distribution of payout to members
  }

  /* Storage */
  address[] emptyArrayAddress; // Empty storage array for initializing new bids (better way to do this?)
  Bid[] public bids; // record of all bids every created
  Bounties public bountiesContract; // current version of the accompanying Bounties contract

  /* Setters */

  // @dev Update the Bounties contract address
  function setBountiesContractAddress(address _address) public onlyOwner returns (bool) {
    bountiesContract = Bounties(_address);
    BountiesContractChanged(_address);
    return true;
  }

  // @dev Transfer bid ownership. New owner must be a member.
  function setOwner(uint256 _id, address _newOwner) public onlyBidOwner(_id) returns (bool) {
    require(_getMemberIndex(_id, _newOwner) >= 0);
    bids[_id].owner = _newOwner;
    BidOwnerChanged(bids[_id].bountyId, _id, _newOwner);
    return true;
  }

  // @dev Change the IPFS hash
  function setData(uint256 _id, string _data) public onlyBidOwner(_id) returns (bool) {
    bids[_id].data = _data;
    BidDataChanged(bids[_id].bountyId, _id, _data);
    return true;
  }

  // @dec Set new shares amount for a member (not cumulative)
  function setShares(uint256 _id, address _address, uint256 _shares) public onlyBidOwner(_id) returns (bool) {
    bids[_id].shares[_address] = _shares;
    BidSharesUpdated(bids[_id].bountyId, _id, _address, _shares);
    return true;
  }

  /* Getters: add more or remove as needed when building UI */

  // @dev Get current status of a Bid
  function getStatus(uint256 _id) public view returns (BidStatus) {
    return (bids[_id].status);
  }

  // @dev Get the total amount paid out to the bid
  function getAmountPaid(uint256 _id) public view returns (uint256) {
    return bids[_id].amountPaid;
  }

  // @dev Return the list of members on this bid (use pointer to ignore trailing deleted rows)
  function getMembers(uint256 _id) public view returns (address[]) {
    return bids[_id].members;
  }

  // @dev Get the index/id for a member address in Bid.members[] (fails if address not found)
  function _getMemberIndex(uint256 _id, address _address) internal view returns (uint256) {
    for (uint256 i=0; i < bids[_id].membersPointer; i++) {
      if (bids[_id].members[i] == _address) { return i; }
    }
  }

  // @dev Get the number of shares for a member on a bid
  function getMemberShares(uint256 _id, address _address) public view returns (uint256) {
    return bids[_id].shares[_address];
  }

  // @dev Sum up the total shares of active members
  function getTotalActiveShares(uint256 _id) public view returns (uint256 shares) {
    for (uint256 i=0; i<bids[_id].membersPointer; i++) {
      shares += bids[_id].shares[bids[_id].members[i]];
    }
  }

  /* Modifiers */

  // @dev Restrict to this contract or Bounties contract
  modifier protected() {
    require(msg.sender == address(bountiesContract) || msg.sender == address(this));
    _;
  }

  // @dev Restrict to accepted bids
  modifier isAccepted(uint256 _id) {
    require(bids[_id].status == BidStatus.Accepted);
    _;
  }

  // @dev Restrict to bid owner
  modifier onlyBidOwner(uint256 _id) {
    require(bids[_id].owner == msg.sender);
    _;
  }

  // @dev Restrict to bid owner or allow address to do something to self
  modifier onlyBidOwnerOrSelf(uint256 _id, address _address) {
    require(msg.sender == bids[_id].owner || msg.sender == _address);
    _;
  }
}
