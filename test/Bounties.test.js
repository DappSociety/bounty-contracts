let Bounties = artifacts.require("BountiesMock")
let PoolMintedToken = artifacts.require("PoolMintedTokenMock")
const zeroAddress = '0x0000000000000000000000000000000000000000'
const oneDay = Math.floor((Date.now() / 1000)) + 86400
const now = Math.floor((Date.now() / 1000))

let accountOne;
let accountTwo;
let bounties;
let token;

// Define Bounty struct and BountyStatus enum
const b = {
  'owner': 0, 'data': 1, 'status': 2, 'maxFunding': 3, 'maxPayout': 4,
  'balance': 5, 'activeId': 6, 'deadline': 7, 'tokenContract': 8}
const s = {
  'Draft': 0, 'Active': 1, 'Closed': 2}

contract('Initialize test vars', async (accounts) => {
  accountOne = accounts[0]
  accountTwo = accounts[1]
  bounties = await Bounties.deployed()
  token = await PoolMintedToken.deployed()
})

contract('Bounty: Create', async (accounts) => {
  it ("should create new bounty", async () => {
    await bounties.create('New Bounty', oneDay, '0x0')
    let totalBounties = await bounties.getBountiesCount.call();
    let bountyId = totalBounties.toNumber()-1; // Doesn't count zero bounty
    let bounty = await bounties.bounties(bountyId);

    assert.isTrue(bounty[b.owner] === accountOne, 'owner')
    assert.isTrue(bounty[b.data] === 'New Bounty', 'data')
    assert.isTrue(bounty[b.balance].toNumber() === 0, 'balance')
    assert.isTrue(bounty[b.activeId].toNumber() === 0, 'activeId')
    assert.isTrue(bounty[b.deadline].toNumber() === oneDay, 'deadline')
    assert.isTrue(bounty[b.status].toNumber() === s.Draft, 'status')
    assert.isTrue(bounty[b.tokenContract] === zeroAddress, 'token contract')
  })

  // it ("should obey senderIsActive modifier", async () => {
  //   // todo: need to implement this modifier first
  // })
})

contract('Bounty: Get Available Tokens', async (accounts) => {
  it ("should get token pool balance", async () => {
    await bounties.create('', oneDay, token.address)

    let bountyId = 0 // zero is taken
    let expectedBalance = 20000 // set in ./mocks/PoolMintTokenMock.sol

    let poolBalance = await bounties.getTokenPoolBalance.call(bountyId)
    assert.isTrue(poolBalance.toNumber() === expectedBalance)
  })

  // todo: create mock function so we can test on multiple tokens
  it ("should get total staked in active bounties", async () => {
    let bountyId = 0
    let amount1 = 300
    let amount2 = 200

    // Add senders as a token delegate
    await token.setPoolDelegate(accountOne, true)
    await token.setPoolDelegate(accountTwo, true)

    // Activate and delegate tokens
    await bounties.activate(bountyId);
    await bounties.delegateTokens(bountyId, amount1)

    // Activate and delegate tokens to two bounties on different "token address"
    await bounties.create('', oneDay, token.address)
    await bounties.activate(1);
    await bounties.delegateTokens(1, amount2)

    // Get the total staked
    let projectOneTotal = await bounties.getBackerActiveAmount(accountOne, token.address)
    assert.isTrue(projectOneTotal.toNumber() === amount1+amount2, 'Project One')
  })

  it ('should get user available tokens from pool', async () => {
    let bountyId = 0
    let poolBalance = 20000;
    let activeMembers = 2; // delegates added above
    let activeDelegated = 500; // amount1 in previous test
    let expected = poolBalance / activeMembers - activeDelegated

    let result = await bounties.getAvailableTokenCount(bountyId, accountOne)
    assert.isTrue(result.toNumber() === expected)
  })
})

contract('Bounty: Close', async (accounts) => {
  // todo: should also test internal function _deactivate in here
  it ("should close draft bounty", async () => {
    let bountyId = 0
    await bounties.create('', oneDay, '0x0')
    await bounties.close(bountyId)

    let bounty = await bounties.bounties(bountyId);
    assert.isTrue(bounty[b.status].toNumber() === s.Closed)
  })

  it ("should close active bounty", async () => {
    let bountyId = 1 // previous test added a bounty
    await bounties.create('', oneDay, '0x0')
    await bounties.activate(bountyId);
    await bounties.close(bountyId)

    let bounty = await bounties.bounties(bountyId);
    assert.isTrue(bounty[b.status].toNumber() === s.Closed)
    assert.isTrue(bounty[b.activeId].toNumber() === 0)
  })

  it ("should obey isNotClosed modifier", async () => {
    let bountyId = 2 // previous test added a bounty
    await bounties.create('', oneDay, '0x0')

    // Test `Closed`
    await bounties.mockSetStatus(bountyId, s.Closed);
    try { await bounties.close(bountyId); assert.fail(); }
    catch (error) {}

    await bounties.mockSetStatus(bountyId, s.Active);
  })

  it ("should obey onlyBountyOwner modifier", async () => {
    let bountyId = 2 // can use bounty from previous test
    await bounties.setOwner(bountyId, accountTwo);

    try { await bounties.close(bountyId); assert.fail(); }
    catch (error) {}
  })
})

contract('Bounty: Activate', async (accounts) => {
  it ("should activate bounty", async () => {
    let bountyId = 0 // constructor adds zero bounty
    await bounties.create('', oneDay, '0x0')
    await bounties.activate(bountyId)

    // check that it is active
    let bounty = await bounties.bounties(bountyId)
    assert.isTrue(bounty[b.status].toNumber() === s.Active, 'active status')

    // make sure it was added to activeBounties array
    let activeBounties = await bounties.getActiveBountiesCount.call('0x0')
    assert.isTrue(activeBounties.toNumber() === 1, 'total active bounties')
    assert.isTrue(bounty[b.activeId].toNumber() === activeBounties.toNumber(), 'activeId')
  })

  it ("should obey canBeActivated modifier", async () => {
    let bountyId = 0 // use bounty from last test

    // Try to activate `Active` bounty
    try { await bounties.activate(bountyId); assert.fail(); }
    catch (error) {}

    // Try to activate `Closed` bounty
    await bounties.mockSetStatus(bountyId, s.Closed);
    try { await bounties.activate(bountyId); assert.fail(); }
    catch (error) {}
  })
})

contract('Bounty: Delegate/Revoke Tokens', async (accounts) => {
  // todo: test for when bounty doesn't exist (delegate and revoke)
  // todo: create mock functions to test from multiple backers, or switch current user?
  it ("should delegate tokens", async () => {
    let bountyId = 0
    let amount = 500

    // Add sender as a token delegate
    await token.setPoolDelegate(accountOne, true)

    await bounties.create('', oneDay, token.address)
    await bounties.activate(bountyId);
    await bounties.delegateTokens(bountyId, amount)

    let bounty = await bounties.bounties(bountyId)
    let backerAmount = await bounties.getBackerAmount(bountyId, accountOne);

    assert.isTrue(bounty[b.balance].toNumber() === amount)
    assert.isTrue(backerAmount.toNumber() === amount)
  })

  it ("should revoke tokens", async () => {
    let bountyId = 0
    let currentAmount = 500 // from previous test
    let revokeAmount = 200
    let expectedAmount = currentAmount - revokeAmount;

    await bounties.revokeTokens(bountyId, revokeAmount);

    let bounty = await bounties.bounties(bountyId)
    let backerAmount = await bounties.getBackerAmount(bountyId, accountOne);

    assert.isTrue(bounty[b.balance].toNumber() === expectedAmount)
    assert.isTrue(backerAmount.toNumber() === expectedAmount)
  })

  it ("should cap revoke amount at backerAmount", async () => {
    let bountyId = 0
    let currentAmount = 300 // from previous tests
    let revokeAmount = 99999999 // more than backerAmount
    let expectedAmount = 0 // should simply revoke all belonging to the sender

    await bounties.revokeTokens(bountyId, revokeAmount)

    let bounty = await bounties.bounties(bountyId)
    let backerAmount = await bounties.getBackerAmount(bountyId, accountOne)

    // restore delegated tokens for next tests
    await bounties.delegateTokens(bountyId, currentAmount)

    assert.isTrue(bounty[b.balance].toNumber() === expectedAmount)
    assert.isTrue(backerAmount.toNumber() === expectedAmount)
  })

  it ("should obey isFundable:status modifier", async () => {
    let bountyId = 0
    let amount = 1

    // Make sure we have enough tokens (to avoid false negative)
    let availableTokens = await bounties.getAvailableTokenCount(bountyId, accountOne)
    assert.isTrue(amount < availableTokens.toNumber(), 'not enough tokens')

    // Test `Draft` bounties
    await bounties.mockSetStatus(bountyId, s.Draft);
    try {await bounties.delegateTokens(bountyId, amount); assert.fail();}
    catch (error) {}
    try {await bounties.revokeTokens(bountyId, amount); assert.fail();}
    catch (error) {}

    // Test `Closed` bounties
    await bounties.mockSetStatus(bountyId, s.Closed);
    try {await bounties.delegateTokens(bountyId, amount); assert.fail();}
    catch (error) {}
    try {await bounties.revokeTokens(bountyId, amount); assert.fail();}
    catch (error) {}
  })

  it ("should obey isFundable:deadline modifier", async () => {
    let bountyId = 0
    let amount = 1

    // Set active, get available tokens, expire
    await bounties.mockSetStatus(bountyId, s.Active);
    let availableTokens = await bounties.getAvailableTokenCount(bountyId, accountOne)
    assert.isTrue(amount < availableTokens.toNumber(), 'not enough tokens')
    await bounties.mockSetDeadline(bountyId, now-1)

    try {await bounties.delegateTokens(bountyId, amount); assert.fail();}
    catch (error) {}
    try {await bounties.revokeTokens(bountyId, amount); assert.fail();}
    catch (error) {}
  })

  it ("should obey hasTokens modifier on delegateTokens", async () => {
    let bountyId = 0
    let amount = 100000

    // Set active, get available tokens, extend deadline
    await bounties.mockSetStatus(bountyId, s.Active)
    let availableTokens = await bounties.getAvailableTokenCount(bountyId, accountOne)
    assert.isTrue(amount > availableTokens.toNumber(), 'has enough tokens')
    await bounties.mockSetDeadline(bountyId, oneDay)

    try {await bounties.delegateTokens(bountyId, amount); assert.fail();}
    catch (error) {}
  })
})

contract('Bounty: Set Owner', async (accounts) => {
  let bountyId = 0;

  it ("should set owner", async () => {
    await bounties.create('New Bounty', oneDay, '0x0')
    await bounties.setOwner(bountyId, accountTwo)
    let bounty = await bounties.bounties(bountyId)
    assert.isTrue(bounty[b.owner] === accountTwo, 'owner')
  })

  it ("should obey onlyBountyOwner modifier", async () => {
    // Owner is now accountTwo from previous test
    try {await bounties.setOwner(bountyId, accountOne); assert.fail();}
    catch (error) {}
  })
})

contract('Bounty: Set Deadline', async (accounts) => {
  // todo: tests for obeying bounty status checks
  let bountyId = 0;

  it ("should extend deadline", async () => {
    let deadline = oneDay;
    let newDeadline = deadline+10

    await bounties.create('New Bounty', deadline, '0x0')
    await bounties.setDeadline(bountyId, newDeadline)
    let bounty = await bounties.bounties(bountyId)
    assert.isTrue(bounty[b.deadline].toNumber() === newDeadline, 'deadline')
  })

  it ("should obey new deadline is greater than now", async () => {
    // Owner is now accountTwo from previous test
    try {await bounties.setDeadline(bountyId, now-1); assert.fail();}
    catch (error) {}
  })
})

// contract('Bounty: Transfer from Token Contract Pool', async (accounts) => {
//   // TODO: this should only be testable from within Bids.sol ~~!! move it there !!~~ (or we could mock it without access control)
//   // todo: test if transferring more than exist in the pool balance
//
//   const accountOne = accounts[0]
//   const accountTwo = accounts[1]
//   let bounties
//   let bountyId = 1
//
//   it ("should transfer tokens", async () => {
//     bounties = await Bounties.deployed()
//     token = await PoolMintedToken.deployed() // PMTMock has 20,000 initial tokens
//     amount = 1000;
//
//     await bounties.create('New Bounty', oneDay, token.address) // Create bounty for the Pool Minted Token
//
//     let initialPoolBalance = await token.balanceOf(token.address)
//
//     // Give bounties contract permission to manage the pool
//     await token.setPoolManager(bounties.address, true)
//     await bounties.transferFromTokenPool(bountyId, accountTwo, amount)
//
//     // Get new token balances
//     let accountTwoBalance = await token.balanceOf(accountTwo)
//     let poolBalance = await token.balanceOf(token.address)
//
//     assert.isTrue(accountTwoBalance.toNumber() === amount, 'account balance');
//     assert.isTrue(poolBalance.toNumber() === initialPoolBalance.toNumber() - amount, 'pool balance')
//   })
//
//
//
//
// })