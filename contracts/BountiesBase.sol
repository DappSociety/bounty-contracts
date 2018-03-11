pragma solidity ^0.4.19;

import "dappsociety-token-contracts/contracts/PoolMintedToken.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "./utils/Array256.sol";
import "./utils/Helpers.sol";
import "./Bids.sol";

/**
 * @title Bounties Base
 * @dev Base functionality and storage for `Bounties.sol`
 * Defines the data structure, basic setters,
 * necessary getters, and modifiers.
 */
contract BountiesBase is Ownable, Helpers {
  using Array256 for uint256[];

  /* Events */
  event BidsContractChanged(address to);
  event BountyOwnerChanged(uint256 bounty, address to);
  event BountyDataChanged(uint256 bounty, string data);
  event BountyMaxFundingChanged(uint256 bounty, uint256 value);
  event BountyMaxPayoutChanged(uint256 bounty, uint256 value);
  event BountyDeadlineChanged(uint256 bounty, uint256 deadline);

  /* Data Structure */
  enum BountyStatus { Draft, Active, Closed }
  struct Bounty {
    address owner; // has all permissions on the bounty (can be human or contract)
    string data; // IPFS hash to json file
    BountyStatus status; // current bounty status
    uint256 maxFunding; // the maximum amount of funding a bounty can receive
    uint256 maxPayout; // the maximum amount any one bid can receive
    uint256 balance; // keeps a tally of total funds allocated and unclaimed
    uint256 activeId; // location in the activesArray (not constant)
    uint256 deadline; // until when it can be worked on or receive funding; can be extended
    PoolMintedToken tokenContract; // a Pool Minted Token contract
    uint256[] bids; // all bids that have been submitted; link to Bids contract
    uint256[] acceptedBids; // all bids that have been accepted as complete
    mapping (address => bool) bidders; // everyone who is on an active bid
    mapping (address => uint256) backers; // everyone who has funded it
  }

  /* Storage */
  uint256[] emptyArray256; // for initializing Bounty structs (better way to do this?)
  Bounty[] public bounties; // record of all bounties ever created
  mapping (address => uint256[]) public actives; // active bounties mapped for each unique token address
  mapping (address => uint256) public activesPointers; // pointers for each active bounties array
  Bids public bidsContract; // current version of the accompanying Bids contract (tightly coupled to Bounties contract)

  /* Setters */

  // @dev Update the Bids contract address
  function setBidsContract(address _address) public onlyOwner returns (bool) {
    bidsContract = Bids(_address);
    BidsContractChanged(_address);
    return true;
  }

  // @dev Change the owner of a bounty.
  function setOwner(uint256 _id, address _newOwner) public onlyBountyOwner(_id) isNotClosed(_id) returns (bool) {
    bounties[_id].owner = _newOwner;
    BountyOwnerChanged(_id, _newOwner);
    return true;
  }

  // @dev Change the IPFS hash
  function setData(uint256 _id, string _data) public onlyBountyOwner(_id) returns (bool) {
    bounties[_id].data = _data;
    BountyDataChanged(_id, _data);
    return true;
  }

  // @dev Set max funding for a bounty.
  function setMaxFunding(uint256 _id, uint256 _value) public onlyBountyOwner(_id) isNotClosed(_id) returns (bool) {
    bounties[_id].maxFunding = _value;
    BountyMaxFundingChanged(_id, _value);
    return true;
  }

  // @dev Set max payout per bid for a bounty.
  function setMaxPayout(uint256 _id, uint256 _value) public onlyBountyOwner(_id) isNotClosed(_id) returns (bool) {
    bounties[_id].maxPayout = _value;
    BountyMaxPayoutChanged(_id, _value);
    return true;
  }

  // @dev Set a new deadline. Must be a time in the future.
  function setDeadline(uint256 _id, uint256 _timestamp) public onlyBountyOwner(_id) isNotClosed(_id) returns (bool) {
    require(_timestamp > now);
    bounties[_id].deadline = _timestamp;
    BountyDeadlineChanged(_id, _timestamp);
    return true;
  }

  // @dev Mark address as bidder on bounty to ensure an address can have only one bid per bounty.
  function _setBidderStatus(uint256 _id, address _address, bool _status) public protected returns (bool) {
    bounties[_id].bidders[_address] = _status;
  }

  // @dev Add a bid ID to the Bounty.bids[] array.
  function _addBid(uint256 _bidId, uint256 _id) public protected returns (bool) {
    bounties[_id].bids.push(_bidId);
  }

  // @dev Add a bid ID to the Bounty.acceptedBids[] array.
  function _addAcceptedBid(uint256 _bidId, uint256 _id) public protected returns (bool) {
    bounties[_id].acceptedBids.push(_bidId);
  }

  /* Getters: add more or remove as needed when building UI */

  // @dev Bounty owner address
  function getOwner(uint256 _id) public view returns (address) {
    return bounties[_id].owner;
  }

  // @dev Current status of a Bounty
  function getStatus(uint256 _id) public view returns (BountyStatus) {
    return bounties[_id].status;
  }

  // @dev Current balance of a Bounty
  function getBalance(uint256 _id) public view returns (uint256) {
    return(bounties[_id].balance);
  }

  // @dev Total number of bounties
  function getBountiesCount() public view returns (uint256) {
    return bounties.length;
  }

  // @dev Active bounties for a given token contract (zero entry not counted)
  function getActiveBountiesCount(address _tokenContract) public view returns (uint256) {
    return activesPointers[_tokenContract]-1;
  }

  // @dev Amount of tokens a backer has delegated to the bounty
  function getBackerAmount(uint256 _bountyId, address _address) public view returns (uint256) {
    return bounties[_bountyId].backers[_address];
  }

  // @dev Sum amount of tokens a user has delegated on all active bounties on a given token
  function getBackerActiveAmount(address _address, address _tokenContract) public view returns (uint256 sum) {
    for (uint256 i=1; i<activesPointers[_tokenContract]; i++) {
      sum += getBackerAmount(actives[_tokenContract][i], _address);
    }
  }

  // @dev Check if an address is on a bid on the bounty
  function isBidder(uint256 _id, address _address) public view returns (bool) {
    return bounties[_id].bidders[_address];
  }

  /* Modifiers */

  // @dev Restrict to this contract or Bids contract
  modifier protected() {
    require(msg.sender == address(bidsContract) || msg.sender == address(this));
    _;
  }

  // @dev Bounty is not closed
  modifier isNotClosed(uint256 _id) {
    require(bounties[_id].status != BountyStatus.Closed);
    _;
  }

  // @dev Bounty does not have activeId and status is Draft
  modifier canBeActivated(uint256 _id) {
    require(bounties[_id].activeId == 0);
    require(bounties[_id].status == BountyStatus.Draft);
    _;
  }

  // @dev Bounty has an activeId set (and then is in an actives[] array)
  modifier canBeDeactivated(uint256 _id) {
    require(bounties[_id].activeId > 0);
    _;
  }

  // @dev Restrict to bounty owner
  modifier onlyBountyOwner(uint256 _id) {
    require(bounties[_id].owner == msg.sender);
    _;
  }

  // @dev Bounty is active, hasn't reached funding cap, and hasn't expired
  modifier canBeFunded(uint256 _bountyId) {
    require(bounties[_bountyId].status == BountyStatus.Active);
    require(bounties[_bountyId].maxFunding == 0 || bounties[_bountyId].balance < bounties[_bountyId].maxFunding);
    require(bounties[_bountyId].deadline > now);
    _;
  }
}
