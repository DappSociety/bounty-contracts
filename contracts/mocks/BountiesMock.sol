pragma solidity ^0.4.19;

import "../Bounties.sol";

contract BountiesMock is Bounties {
  function mockSetStatus(uint256 _id, BountyStatus _status) public returns (bool) {
    bounties[_id].status = _status;
    return true;
  }

  function mockSetDeadline(uint256 _id, uint256 _timestamp) public returns (bool) {
    bounties[_id].deadline = _timestamp;
    return true;
  }
}
