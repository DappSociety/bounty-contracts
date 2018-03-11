let Bounties = artifacts.require('BountiesMock');
let Bids = artifacts.require('BidsMock');
let PoolMintedToken = artifacts.require('PoolMintedTokenMock');
let Array256 = artifacts.require('Array256');
let Helpers = artifacts.require('Helpers');
let ArrayAddress = artifacts.require('ArrayAddress');
let SafeMath = artifacts.require('SafeMath');
module.exports = function (deployer) {
  deployer.deploy(PoolMintedToken);
  deployer.deploy(Array256);
  deployer.deploy(ArrayAddress);
  deployer.deploy(SafeMath);
  deployer.link(Array256, Bounties);
  deployer.link(SafeMath, Helpers);
  deployer.link(SafeMath, Bids);
  deployer.link(ArrayAddress, Bids);
  deployer.deploy(Bids);
  deployer.deploy(Bounties);

};
