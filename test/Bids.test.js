let Bounties = artifacts.require('BountiesMock')
let PoolMintedToken = artifacts.require('PoolMintedTokenMock')
let Bids = artifacts.require('BidsMock')
const zeroAddress = '0x0000000000000000000000000000000000000000'
const oneDay = Math.floor((Date.now() / 1000)) + 86400
const now = Math.floor((Date.now() / 1000))

// Define Bounty struct and BountyStatus enum
const b = {
  'owner': 0, 'data': 1, 'status': 2, 'bountyId': 3,
  'amountPaid': 4, 'membersPointer': 5}
const s = {
  'Active': 0, 'Withdrawn': 1, 'Rejected': 2, 'Accepted': 3}

contract('Bids: ', async (accounts) => {
  const accountOne = accounts[0]
  const accountTwo = accounts[1]
  let bounties
  let token
  let bids
  let bountyId = 0
  let bidId = 0

  // todo: check the Bid.members array
  // todo: check the Bounty.bids array (or just check this in Bounties.sol?)
  // todo: check with inactive bounty
  // todo: write dedicated test for getTotalActiveShares
  it ("should create new bid", async () => {
    bids = await Bids.deployed()
    bounties = await Bounties.deployed()
    token = await PoolMintedToken.deployed()

    await bids.setBountiesContractAddress(bounties.address) // link contracts
    await bounties.setBidsContract(bids.address) // link contracts
    await bounties.create('Bounty Data', oneDay, token.address) // create bounty
    await bounties.activate(bountyId) // must activate it
    await bids.create(bountyId, 'Bid Data')

    // check the bid
    let bid = await bids.bids(bidId);
    assert.isTrue(bid[b.owner] === accountOne, 'owner')
    assert.isTrue(bid[b.data] === 'Bid Data', 'data')
    assert.isTrue(bid[b.status].toNumber() === s.Active, 'status')
    assert.isTrue(bid[b.bountyId].toNumber() === bountyId, 'bountyId')
    assert.isTrue(bid[b.membersPointer].toNumber() === 1, 'membersPointer')
  })

  // todo: test with all modifiers
  it ("should add new member to bid", async () => {
    await bids.addMember(bidId, accountTwo, 500)

    // check members pointer
    let bid = await bids.bids(bidId)
    assert.isTrue(bid[b.membersPointer].toNumber() === 2, 'membersPointer')

    // check bidder status
    let isBidder = await bounties.isBidder(bountyId, accountTwo)
    assert.isTrue(isBidder)
  })

  // todo: test with modifiers
  // todo: test that removing bid owner fails
  it ("should remove member from bid", async () => {
    await bids.removeMember(bidId, accountTwo)

    // check members pointer
    let bid = await bids.bids(bidId)
    assert.isTrue(bid[b.membersPointer].toNumber() === 1, 'membersPointer')

    // check bidder status
    let isBidder = await bounties.isBidder(bountyId, accountTwo)
    assert.isFalse(isBidder)
  })

  // todo: test modifiers and requires
  it ("should transfer bid ownership", async () => {
    await bids.addMember(bidId, accountTwo, 500)
    await bids.setOwner(bidId, accountTwo)

    let bid = await bids.bids(bidId)
    assert.isTrue(bid[b.owner] === accountTwo, 'owner')

    await bids.mockSetOwner(bidId, accountOne) // revert ownership
  })

  // todo: test modifiers
  it ("should withdraw bid", async () => {
    await bids.withdraw(bidId)

    let bid = await bids.bids(bidId)
    assert.isTrue(bid[b.status].toNumber() === s.Withdrawn, 'status')

    await bids.mockSetStatus(bidId, s.Active) // set status back to active
  })

  // todo: test various cases (break out to its own test)
  it ("should set member shares", async () => {
    let oneAmount = 2
    let twoAmount = 1

    await bids.setShares(bidId, accountOne, oneAmount)
    await bids.setShares(bidId, accountTwo, twoAmount)

    let accountOneShares = await bids.getMemberShares(bidId, accountOne)
    let accountTwoShares = await bids.getMemberShares(bidId, accountTwo)

    assert.isTrue(accountOneShares.toNumber() === oneAmount)
    assert.isTrue(accountTwoShares.toNumber() === twoAmount)

    // Revert shares
    await bids.setShares(bidId, accountOne, 1000)
    await bids.setShares(bidId, accountTwo, 500)
  })

  // todo: test various cases (break out to its own test)
  // it ("should payout tokens on member shares", async () => {
  //   let initialPoolBalance = 20000
  //   let accountOneShares = 1000
  //   let accountTwoShares = 500
  //   let totalShares = accountOneShares + accountTwoShares
  //   let bountyBalance = 3000
  //
  //   let availableTokens = await bounties.getAvailablePoolTokens(bountyId, accountOne);
  //   availableTokens = availableTokens.toNumber();
  //   assert.isTrue(availableTokens >= bountyBalance, 'delegating too many tokens; accountOne has ' + availableTokens)
  //
  //   let accountOneExpected = Math.floor((accountOneShares/totalShares) * bountyBalance)
  //   let accountTwoExpected = Math.floor((accountTwoShares/totalShares) * bountyBalance)
  //
  //   await bounties.setBidsContractAddress(bids.address);
  //
  //   // Give bounties contract permission to manage the pool
  //   await token.setPoolManager(bounties.address, true)
  //
  //   await bounties.delegateTokens(bountyId, bountyBalance) // delegate some tokens
  //   await bids.accept(bidId)
  //   await bounties.complete(bountyId) // mark this bid as the winner
  //
  //   // ------ TEMP ANOTHER BID todo: remove ------- //
  //   await bounties.mockSetStatus(bountyId, 1);
  //   await bids.create(bountyId, 'Bid Data 2') // submit another bid
  //   await bids.accept(1);
  //
  //   await bounties.payout(bountyId)
  //
  //   bountyBalance = await bounties.getBalance(bountyId)
  //   let poolBalance = await token.balanceOf(token.address)
  //   let accountOneBalance = await token.balanceOf(accountOne);
  //   let accountTwoBalance = await token.balanceOf(accountTwo);
  //
  //   console.log([
  //     bountyBalance.toNumber(), accountOneBalance.toNumber(),
  //     accountTwoBalance.toNumber(), poolBalance.toNumber()
  //   ])
  //
  //   // assert.isTrue(accountOneBalance.toNumber() === accountOneExpected, 'account one')
  //   // assert.isTrue(accountTwoBalance.toNumber() === accountTwoExpected, 'account two')
  //   // assert.isTrue(poolBalance.toNumber() === initialPoolBalance-accountOneBalance.toNumber()-accountTwoBalance.toNumber(), 'pool')
  //
  // })

  it ("should obey max token payout", async () => {
    let initialPoolBalance = 20000
    let accountOneShares = 1 // equal shares should split max payout
    let accountTwoShares = 1
    let totalShares = accountOneShares + accountTwoShares
    let bountyBalance = 1000

    // Add sender as a token delegate
    await token.setPoolDelegate(accountOne, true)

    await bids.setShares(bidId, accountOne, accountOneShares)
    await bids.setShares(bidId, accountTwo, accountTwoShares)

    await token.setPoolManager(bounties.address, true)

    let availableTokens = await bounties.getAvailableTokenCount(bountyId, accountOne);
    availableTokens = availableTokens.toNumber();
    assert.isTrue(availableTokens >= bountyBalance, 'delegating too many tokens; accountOne has ' + availableTokens)

    let accountOneExpected = Math.floor((accountOneShares/totalShares) * bountyBalance)
    let accountTwoExpected = Math.floor((accountTwoShares/totalShares) * bountyBalance)

    // set the bounty active
    await bounties.mockSetStatus(bountyId, 1);

    // set a max payout of 10
    await bounties.setMaxPayout(bountyId, 10);

    await bounties.delegateTokens(bountyId, bountyBalance) // delegate some tokens
    await bids.accept(bidId)  // mark this bid as the winner

    // todo: test batches
    await bounties.payout(bountyId, 0)

    // Add another bid and payout again
    await bids.create(bountyId, 'Bid 2 Data', {from: accounts[2]}) // submit another bid
    await bids.accept(1);
    await bounties.payout(bountyId, 0)

    bountyBalance = await bounties.getBalance(bountyId)
    let poolBalance = await token.balanceOf(token.address)
    let accountOneBalance = await token.balanceOf(accountOne)
    let accountTwoBalance = await token.balanceOf(accountTwo)

    console.log([
      bountyBalance.toNumber(), accountOneBalance.toNumber(),
      accountTwoBalance.toNumber(), poolBalance.toNumber()
    ])

    // assert.isTrue(accountOneBalance.toNumber() === accountOneExpected, 'account one')
    // assert.isTrue(accountTwoBalance.toNumber() === accountTwoExpected, 'account two')
    // assert.isTrue(poolBalance.toNumber() === initialPoolBalance-accountOneBalance.toNumber()-accountTwoBalance.toNumber(), 'pool')

  })

  // todo: test payouts to multiple bids
  // todo: test payout with
  // it ("should get accepted bids", async () => {
  //   await bounties.mockSetStatus(bountyId, 1);
  //   await bids.create(bountyId, 'Bid Data 2') // submit another bid
  //   await bids.accept(1);
  //
  //   let acceptedBids = await bounties.getAcceptedBids(bountyId)
  //   console.log(acceptedBids)
  // })


})