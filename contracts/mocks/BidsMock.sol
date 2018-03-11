pragma solidity ^0.4.19;

import "../Bids.sol";

contract BidsMock is Bids {
  function mockSetOwner(uint256 _id, address _address) public returns (bool) {
    bids[_id].owner = _address;
    return true;
  }

  function mockSetStatus(uint256 _id, BidsBase.BidStatus _status) public returns (bool) {
    bids[_id].status = _status;
    return true;
  }
}
