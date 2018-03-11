pragma solidity ^0.4.19;

import "dappsociety-token-contracts/contracts/PoolMintedToken.sol";

contract PoolMintedTokenMock is PoolMintedToken {
  uint256 public constant initialSupply = 20000;

  function PoolMintedTokenMock() public {
    totalSupply_ += initialSupply;
    balances[this] = initialSupply;
    Transfer(0x0, this, initialSupply);
    timeOfLastMint = now;
  }
}
