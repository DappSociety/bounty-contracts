pragma solidity ^0.4.19;

import "./BountiesBase.sol";

/**
 * @title Bounties
 * @dev A bounties implementation characterized by the ability for
 * members to delegate tokens from a shared pool towards a bounty
 * being completed.
 */
contract Bounties is BountiesBase {
  /* Events */
  event BountyAdded(uint256 bounty);
  event BountyActivated(uint256 bounty);
  event BountyClosed(uint256 bounty);
  event TokensDelegated(uint256 bounty, address by, uint256 value, uint256 balance);
  event TokensRevoked(uint256 bounty, address by, uint256 value, uint256 balance);

  /**
   * @dev Creates a new Bounty and adds it to `bounties[]`
   * - Currently allows anyone to create bounties. But only certain users (per token)
   *   can delegate tokens from the pool to it. After working on governance there
   *   will likely be a friendly way to restrict who can create them.
   * @param _data IPFS hash to a properly formatted JSON file
   * @param _deadline A timestamp for when the bounty expires
   * @param _tokenContract The Pool Minted Token that this bounty uses
   * @return The position in `bounties[]`
   */
  function create(string _data, uint256 _deadline, address _tokenContract) public returns (uint256) {
    bounties.push(Bounty(
      msg.sender, _data, BountyStatus.Draft, 0, 0, 0, 0, _deadline,
      PoolMintedToken(_tokenContract), emptyArray256, emptyArray256
    ));
    // Create dummy active bounty [0] so we can use `Bid.activeId = 0` as an empty value
    if (actives[_tokenContract].length == 0) {
      activesPointers[_tokenContract] = actives[_tokenContract].addRow(0, activesPointers[_tokenContract]);
    }
    BountyAdded(bounties.length-1);
    return bounties.length-1;
  }

  /**
   * @dev Activate a bounty
   * @param _id The bounty to activate
   */
  function activate(uint256 _id) public canBeActivated(_id) onlyBountyOwner(_id) returns (bool) {
    address token = bounties[_id].tokenContract;
    activesPointers[token] = actives[token].addRow(_id, activesPointers[token]);
    bounties[_id].activeId = activesPointers[token]-1;
    bounties[_id].status = BountyStatus.Active;
    BountyActivated(_id);
    return true;
  }

  /**
   * @dev Close a bounty. No changes can be made but balance can still be paid out.
   * @param _id The bounty to activate
   */
  function close(uint256 _id) public isNotClosed(_id) onlyBountyOwner(_id) returns (bool) {
    if (bounties[_id].status == BountyStatus.Active) _deactivate(_id);
    bounties[_id].status = BountyStatus.Closed;
    BountyClosed(_id);
    return true;
  }

  /**
   * @dev Deactivate a bounty and remove from actives array
   * - If it is not the last element in its token's `actives[]`, then transfer
   *   this bounty's `activeId` to the one that takes its place
   * @param _id The bounty to activate
   */
  function _deactivate(uint256 _id) internal canBeDeactivated(_id) returns (bool) {
    address token = bounties[_id].tokenContract;
    uint256 activeId = bounties[_id].activeId;
    bounties[_id].activeId = 0;
    activesPointers[token] = actives[token].deleteRow(activeId, activesPointers[token]);
    if (activeId < activesPointers[token]) bounties[activesPointers[token]].activeId = activeId;
    return true;
  }

  /**
   * @dev Delegate tokens towards the bounty balance.
   * - Doesn't actually transfer any tokens and so is reversed automatically if bounty is killed.
   * @param _id The bounty ID
   * @param _value The amount to delegate
   */
  function delegateTokens(uint256 _id, uint256 _value)
  public canBeFunded(_id) canDelegateTokens(msg.sender, _id, _value) returns (bool) {
    _value = getCappedAmount(bounties[_id].balance, _value, bounties[_id].maxFunding);
    require(_value > 0);
    bounties[_id].balance = bounties[_id].balance.add(_value);
    bounties[_id].backers[msg.sender] = bounties[_id].backers[msg.sender].add(_value);
    TokensDelegated(_id, msg.sender, _value, bounties[_id].balance);
    return true;
  }

  /**
   * @dev Revoke previously delegated tokens on a bounty.
   * - It is possible the revoker will have less available than revoked because
   *   they go back into the shared pool calculation.
   * - Don't need to restrict who can call this because users without permission
   *   will have a current amount of zero.
   * @param _id The bounty ID
   * @param _value The amount to revoke; capped at total delegated by the user
   */
  function revokeTokens(uint256 _id, uint256 _value) public canBeFunded(_id) returns (bool) {
    uint256 currentAmount = getBackerAmount(_id, msg.sender);
    if (_value > currentAmount) _value = currentAmount;
    require(_value > 0);
    bounties[_id].balance = bounties[_id].balance.sub(_value);
    bounties[_id].backers[msg.sender] = bounties[_id].backers[msg.sender].sub(_value);
    TokensRevoked(_id, msg.sender, _value, bounties[_id].balance);
    return true;
  }

  /**
   * @dev Payout current bounty balance to all accepted bids
   * - Does not matter who calls this; they are simply doing the payees a favor by paying gas fees
   * - Payees have incentive to call it as soon as they can (while funds are sufficient for number of bids)
   * - Contains unbounded loop; likely to run out of gas if too many accepted+payable bids and `batchSize=0`
   * - Events are emitted in Bids.payout
   * - See documentation for examples scenarios, possible problems, and how they can be avoided [add link]
   * @param _id The bounty ID
   * @param _batchSize How many bids to payout before returning; 0 for unlimited
   */
  function payout(uint256 _id, uint256 _batchSize) public returns (bool) {
    uint256 payableBids = getPayableBidsCount(_id);
    require(payableBids > 0);
    uint256 amountPerBid = bounties[_id].balance / payableBids; // all payable bids share the balance equally
    // if batching, there must be enough balance to go around
    if (_batchSize > 0) {
      require(bounties[_id].maxPayout > 0);
      require(amountPerBid >= bounties[_id].maxPayout);
    }
    // loop through all accepted bids (Bids.payout only pays on payable bids)
    for (uint256 i=0; i<bounties[_id].acceptedBids.length; i++) {
      if (_batchSize != 0 && i == _batchSize) return true;
      bounties[_id].balance -= bidsContract._payout(bounties[_id].acceptedBids[i], amountPerBid, bounties[_id].maxPayout);
    }
    return true;
  }

  /**
   * @dev Total accepted bids that have not reached the max payout
   * @param _id The bounty ID
   * todo: if this can return an array of ids, it would improve the loop in `payout()`
  */
  function getPayableBidsCount(uint256 _id) public view returns (uint256 payableBids) {
    if (bounties[_id].maxPayout == 0) return bounties[_id].acceptedBids.length;
    for (uint256 i=0; i<bounties[_id].acceptedBids.length; i++) {
      if (bidsContract.getAmountPaid(bounties[_id].acceptedBids[i]) < bounties[_id].maxPayout) payableBids++;
    }
  }

  /* External Calls */

  /**
   * @dev Transfer from the bounty's token shared pool
   * - This contract must have `poolManager` permissions on the token contract.
   * - Should be considered a protected/internal function because only Bids can use it.
   * - Events are emitted elsewhere; including on the token contract.
   * @param _id The bounty ID
   * @param _recipient Which address should receive the tokens
   * @param _value How many tokens to transfer
   */
  function _transferFromTokenPool(uint256 _id, address _recipient, uint256 _value) public protected returns (bool) {
    require(bounties[_id].tokenContract.transferFromPool(_recipient, _value));
    return true;
  }

  // @dev Balance of a token contract shared pool
  function getTokenPoolBalance(uint256 _id) public view returns (uint256) {
    return bounties[_id].tokenContract.balanceOf(bounties[_id].tokenContract);
  }

  // @dev Total number of token delegates on a token contract (how many are sharing the pool)
  function getTokenDelegatesCount(uint256 _id) public view returns (uint256) {
    return bounties[_id].tokenContract.poolDelegatesCount();
  }

  // @dev How many tokens from the shared pool (on a given token contract) an address can delegate
  function getAvailableTokenCount(uint256 _bountyId, address _member) public view returns (uint256) {
    require(bounties[_bountyId].tokenContract.isPoolDelegate(_member));
    uint256 delegatedTokens = getBackerActiveAmount(_member, bounties[_bountyId].tokenContract);
    uint256 delegatesCount = getTokenDelegatesCount(_bountyId);
    require(delegatesCount > 0);
    return (getTokenPoolBalance(_bountyId) / getTokenDelegatesCount(_bountyId) - delegatedTokens);
  }

  /* Modifiers */

  // @dev Make sure address has enough available tokens and is a pool delegate
  modifier canDelegateTokens(address _member, uint256 _bountyId, uint256 _value) {
    require(bounties[_bountyId].tokenContract.isPoolDelegate(_member));
    require(getAvailableTokenCount(_bountyId, _member) >= _value);
    _;
  }
}
