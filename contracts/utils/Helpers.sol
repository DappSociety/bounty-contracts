pragma solidity ^0.4.19;

import "zeppelin-solidity/contracts/math/SafeMath.sol";

contract Helpers {
  using SafeMath for uint256;

  // @dev Generic function to cap a value; use `_cap=0` for no cap
  function getCappedAmount(uint256 _current, uint256 _toAdd, uint256 _cap) public pure returns (uint256) {
    if (_cap == 0) return _toAdd; // no cap
    if (_current.add(_toAdd) > _cap) return _cap.sub(_current); // partial amount
    if (_cap.sub(_current) <= 0) return 0; // cap reached
    return _toAdd; // does not exceed cap
  }
}
