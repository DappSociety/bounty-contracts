pragma solidity ^0.4.19;

import "./BidsBase.sol";

/**
 * @title Bids
 * @dev Tightly-coupled to Bounties. Handles all submissions and payouts.
 */
contract Bids is BidsBase {

  /* Events */
  event BidAdded(uint256 bounty, uint256 bid);
  event BidMemberAdded(uint256 bounty, uint256 bid, address who, uint256 shares);
  event BidMemberRemoved(uint256 bounty, uint256 bid, address who);
  event BidWithdrawn(uint256 bounty, uint256 bid);
  event BidRejected(uint256 bounty, uint256 bid);
  event BidAccepted(uint256 bounty, uint256 bid);
  event BidMemberPaid(uint256 bounty, uint256 bid, address to, uint256 value);

  /**
   * @dev Creates a new Bid and adds it to `bids[]`.
   * - Owner (msg.sender) is given 1000 initial shares (gives flexibility for assigning new member weighted shares)
   * @param _bountyId The Bounty this bid is being submitted to
   * @param _data IPFS hash to a properly formatted JSON file
   * @return The position in `bids[]`
   */
  function create(uint256 _bountyId, string _data) public bountyIsActive(_bountyId) returns (uint256 id) {
    bids.push(Bid(msg.sender, _data, BidStatus.Active, _bountyId, 0, 0, emptyArrayAddress));
    id = bids.length-1;
    addMember(id, msg.sender, 1000);
    bountiesContract._addBid(id, _bountyId);
    BidAdded(_bountyId, id);
  }

  /**
   * @dev Adds a new member onto a bid.
   * - msg.sender is designed the owner
   * - Owner is given 1000 initial shares (gives flexibility for assigning new member weighted shares)
   * @param _id The Bid to add the member to
   * @param _address The new member's address
   * @param _shares How many shares to give them (no cap; simply dilutes existing members)
   */
  function addMember(uint256 _id, address _address, uint256 _shares)
  public onlyBidOwner(_id) notBidderOnBounty(_id, _address) returns (bool) {
    bids[_id].membersPointer = bids[_id].members.addRow(_address, bids[_id].membersPointer);
    bountiesContract._setBidderStatus(bids[_id].bountyId, _address, true);
    bids[_id].shares[_address] = _shares;
    BidMemberAdded(bids[_id].bountyId, _id, _address, _shares);
    return true;
  }

  /**
   * @dev Remove a member from a bid. Can be down by bid owner or self.
   * - Also releases address from Bounty so free to create or join another bid on it.
   * - Bid owner must be a member, and so cannot remove self without transferring ownership first
   * @param _id The Bid to add the member to
   * @param _address The new member's address
   */
  function removeMember(uint256 _id, address _address) public onlyBidOwnerOrSelf(_id, _address) returns (bool) {
    require(_address != bids[_id].owner);
    bountiesContract._setBidderStatus(bids[_id].bountyId, _address, false);
    bids[_id].membersPointer = bids[_id].members.deleteRow(_getMemberIndex(_id, _address), bids[_id].membersPointer);
    bids[_id].shares[_address] = 0;
    BidMemberRemoved(bids[_id].bountyId, _id, _address);
    return true;
  }

  /**
   * @dev Withdraw a bid from the bounty
   * - Members must still manually remove if they want to be on a new bid for the same bounty
   * - Bid remains in the the bids[] and Bounty.acceptedBids[] arrays as a historical record
   * - Withdrawing an accepted bid means it can no longer receive any more funds
   * @param _id The Bid to withdraw
   */
  function withdraw(uint256 _id) public onlyBidOwner(_id) returns (bool) {
    require(bids[_id].status != BidStatus.Rejected);
    bids[_id].status = BidStatus.Withdrawn;
    BidWithdrawn(bids[_id].bountyId, _id);
    return true;
  }

  /**
   * @dev Reject a bid from the bounty
   * - Members must still manually remove if they want to be on a new bid for the same bounty
   * - Bid remains in the the bids[] array as a historical record
   * - Cannot reject a bid that has already been accepted
   * @param _id The Bid to withdraw
   */
  function reject(uint256 _id) public onlyBountyOwner(_id) returns (bool) {
    require(bids[_id].status != BidStatus.Accepted);
    bids[_id].status = BidStatus.Rejected;
    BidRejected(bids[_id].bountyId, _id);
    return true;
  }

  /**
   * @dev Accept a bid
   * @param _id The Bid to accept
   */
  function accept(uint256 _id) public onlyBountyOwner(_id) returns (bool) {
    bountiesContract._addAcceptedBid(_id, bids[_id].bountyId);
    bids[_id].status = BidStatus.Accepted;
    BidAccepted(bids[_id].bountyId, _id);
    return true;
  }

  /**
   * @dev Payout all members of the bid according to their relative shares
   * @param _id The Bid to payout
   * @param _value The amount to pay to the bid (Bounty.balance / Bounty payableBids)
   * @param _maxPayout The max payout per bid for the Bounty
   */
  function _payout(uint256 _id, uint256 _value, uint256 _maxPayout)
  public isAccepted(_id) protected returns (uint256 totalPaidOut) {
    _value = getCappedAmount(bids[_id].amountPaid, _value, _maxPayout);
    if (_value <= 0) return 0;
    // Loop through and pay active members
    uint256 totalShares = getTotalActiveShares(_id); // Get once
    for (uint256 i=0; i<bids[_id].membersPointer; i++) {
      totalPaidOut += _payoutMember(_id, i, _value, totalShares);
    }
    bids[_id].amountPaid = bids[_id].amountPaid.add(totalPaidOut);
    assert(bids[_id].amountPaid <= _maxPayout);
  }

  /**
   * @dev Payout an individual bid member
   * @param _id The Bid
   * @param _memberId The member ID in Bid.members[]
   * @param _value The amount to pay this member
   * @param _totalShares The sum of all member shares on the bid
   */
  function _payoutMember(uint256 _id, uint256 _memberId, uint256 _value, uint256 _totalShares)
  internal returns (uint256 value) {
    address memberAddress = bids[_id].members[_memberId];
    value = _value * bids[_id].shares[memberAddress] / _totalShares;
    require(bountiesContract._transferFromTokenPool(bids[_id].bountyId, memberAddress, value));
    BidMemberPaid(bids[_id].bountyId, _id, memberAddress, value);
  }

  /* Modifiers */

  // @dev Restrict to active bounties
  modifier bountyIsActive(uint256 _bountyId) {
    require(bountiesContract.getStatus(_bountyId) == BountiesBase.BountyStatus.Active);
    _;
  }

  // @dev Address is not already a member if a bid on the Bounty
  modifier notBidderOnBounty(uint256 _bidId, address _address) {
    require(!bountiesContract.isBidder(bids[_bidId].bountyId, _address));
    _;
  }

  // @dev Restrict to Bounty owner
  modifier onlyBountyOwner(uint256 _bidId) {
    require(bountiesContract.getOwner(bids[_bidId].bountyId) == msg.sender);
    _;
  }
}
