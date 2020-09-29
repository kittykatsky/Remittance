/* xxx
 *
 * Tests for xxx contract.
 * All test refers to the xxx contract (it)
 * unless otherwise specifed.
 *
 * tests require min. 3 accounts
 *
 * */

const { BN, fromAscii } = web3.utils;
const chai = require('chai');
var chaiAsPromised = require("chai-as-promised");
chai.use(chaiAsPromised);
const expect = chai.expect;
const truffleAssert = require('truffle-assertions');
const Remittance = artifacts.require('Remittance');
const timeMachine = require('ganache-time-traveler');

require("dotenv").config({path: "./.env"});

contract('Remittance', function(accounts) {

    let remittance, puzzle, trx, snapshotId;
    const [aliceAccount, bobAccount, carolAccount] = accounts;

    const converter = carolAccount;
    const recipient = bobAccount;
    const remFee = 2000;
    const rPuzzle = fromAscii(process.env.PUZZLE_RECIPIENT);
    const rPuzzleSec = fromAscii(process.env.PUZZLE_RECIPIENT_SECONDARY);


    beforeEach('Setup new Remittance before each test', async function () {
        const snapshot = await timeMachine.takeSnapshot();
        snapshotId = snapshot['result'];
        remittance = await Remittance.new(false, remFee, {from: aliceAccount});
        puzzle = await remittance.generatePuzzle(converter, rPuzzle, {from: aliceAccount})
        trx = await remittance.createRemittance(puzzle, 10, {from: aliceAccount, value:5000});
    });

    afterEach(async() => {
        await timeMachine.revertToSnapshot(snapshotId);
    });

    describe('deployment', function () {

        it("Should have the deployer as its owner and be in the created state", async function () {
            return expect(await remittance.getOwner()).to.equal(aliceAccount)
        });

        it("Should have a puzzle associate with a struct holding sender, \
        amount and deadline", async function () {
            remittances = await remittance.remittances(puzzle);

            const block = await web3.eth.getBlock(trx.receipt.blockNumber);
            const setDeadline = block.timestamp + 10;
            assert.strictEqual(remittances.from, aliceAccount);
            assert.strictEqual(remittances.deadline.toString(), setDeadline.toString());
            return assert.strictEqual(remittances.amount.toString(), '3000');
        });

        it("Should not be possible to generate the same secret from two seperte contracts", async function () {
            const remittance2 = await Remittance.new(false, remFee, {from: aliceAccount});
            assert.notEqual(
                await remittance.generatePuzzle(converter, rPuzzle, {from: aliceAccount}),
                await remittance2.generatePuzzle(converter, rPuzzle, {from: aliceAccount})
            )
        });

        it("Should be possible to change owner", async function () {
            await remittance.transferOwnership(bobAccount, {from: aliceAccount});
            assert.strictEqual(bobAccount,
                await remittance.getOwner({from: bobAccount})
            );
        });

        it("Should be possible for the old owner to get back their fees when changing owner", async function () {
            await remittance.transferOwnership(bobAccount, {from: aliceAccount});

            const originalBalance = await web3.eth.getBalance(aliceAccount);
            const trx = await remittance.withdrawFees({from: aliceAccount});
            const trxTx = await web3.eth.getTransaction(trx.tx);

            const gasUsed = new BN(trx.receipt.gasUsed);
            const gasPrice = new BN(trxTx.gasPrice);
            const gasCost = gasPrice.mul(gasUsed);

            const expectedBalance = new BN(originalBalance).sub(gasCost).add(new BN(remFee));
            const actualBalance = new BN(await web3.eth.getBalance(aliceAccount));

            assert.strictEqual(expectedBalance.toString(), actualBalance.toString());
        });
    });

    describe('Pausable', function () {

        it("Should be owned by the deployer", async function () {
            return expect(await remittance.getOwner()).to.equal(aliceAccount)
        });

        it("Should not be possible to withdraw when paused", async function () {
            await remittance.pause({from: aliceAccount})
            return expect(remittance.releaseFunds(puzzle, {from: converter})).to.be.rejected;
        });

        it("Should be possible to kill a paused contract", async function () {
            await remittance.pause({from: aliceAccount});
            const tx = await remittance.kill({from: aliceAccount});
            return assert.strictEqual(tx.receipt.status, true);
        });

        it("Should no be possible to run a killed contract", async function () {
            await remittance.pause({from: aliceAccount});
            return expect(remittance.releaseFunds(puzzle, {from: converter})).to.be.rejected;
        });

        it("Should not be possible to unpause a killed contract", async function () {
            await remittance.pause({from: aliceAccount});
            await remittance.kill({from: aliceAccount});
            return expect(remittance.resume({from: aliceAccount})).to.be.rejected;
        });

        it("Should not be possible to empty a live contract", async function () {
            return expect(remittance.emptyAccount(aliceAccount, {from: aliceAccount})).to.be.rejected;
        });

        it("Should be possible to empty a killed contract", async function () {
            await remittance.pause({from: aliceAccount});
            await remittance.kill({from: aliceAccount});
            return expect(remittance.emptyAccount(aliceAccount, {from: aliceAccount})).to.be.fulfilled;
        });
    });

    describe('remittance', function (){

        it("Should not be possible to release the Remittance" +
            "without the right puzzle or right wrong account", async function () {
            const wrongPuzzle = remittance.generatePuzzle(converter, rPuzzleSec, {from: aliceAccount})
            expect(remittance.releaseFunds(
                wrongPuzzle,
                {from: converter}
            )).to.be.rejected;
            return expect(remittance.releaseFunds(rPuzzle, {from: aliceAccount})).to.be.rejected;
        });


        it("Should be possible to release the remittance with the correct puzzle", async function () {
            return expect(remittance.releaseFunds(rPuzzle, {from: converter})).to.be.fulfilled;
        });

        it("Should not be possible to release the Remittance after its been released", async function () {
            remittance.releaseFunds(rPuzzle, {from: converter});
            return expect(remittance.releaseFunds(rPuzzle, {from: converter})).to.be.rejected;
        });

        it("Should send all the ether stored in the remittance to the converter after release", async function () {

            const originalBalance= await web3.eth.getBalance(converter);

            const trx = await remittance.releaseFunds(rPuzzle, {from: converter});
            const trxTx = await web3.eth.getTransaction(trx.tx);

            const gasUsed = new BN(trx.receipt.gasUsed);
            const gasPrice = new BN(trxTx.gasPrice);
            const gasCost = gasPrice.mul(gasUsed);

            const expectedBalance = new BN(originalBalance).sub(gasCost).add(new BN(3000));
            const actualBalance = new BN(await web3.eth.getBalance(converter));

            return assert.strictEqual(actualBalance.toString(), expectedBalance.toString());
        });

        it("Should be possible for Alice to verify that the transaction went through", async function () {

            const tx = await remittance.releaseFunds(
                rPuzzle, {from: converter}
            );

            truffleAssert.eventEmitted(tx, 'LogFundsReleased', (ev) => {
                return ev.converter === converter && ev.puzzle === puzzle && ev.amount.toString() === '3000'
            });
        });

        it("Should be possible to verify that a remittance was reclaimed", async function () {

            await timeMachine.advanceTimeAndBlock(11);
            const tx = await remittance.reclaimFunds(
                puzzle, {from: aliceAccount}
            );

            truffleAssert.eventEmitted(tx, 'LogFundsReclaimed', (ev) => {
                return ev.sender === aliceAccount && ev.amount.toString() === '3000'
            });
        });

        it("Should be possible to verify that a new remittance has been created", async function () {
            const newPuzzle = await remittance.generatePuzzle(converter, rPuzzleSec, {from: aliceAccount})
            const trx = await remittance.createRemittance(newPuzzle, 10, {from: aliceAccount, value:5000});

            truffleAssert.eventEmitted(trx, 'LogNewRemittance', (ev) => {
                return ev.sender === aliceAccount && ev.puzzle === newPuzzle && ev.amount.toString() === '3000'
            });
        });

        it("Should be possible to create several remittances on the same contract", async function () {
            const newPuzzle = await remittance.generatePuzzle(converter, rPuzzleSec, {from: aliceAccount})
            return expect(remittance.createRemittance(
                newPuzzle,
                10,
                {from: aliceAccount, value:3000}
            )).to.be.fulfilled;
        });

        it("Should not be possible to create a remittance with the same puzzle", async function () {
            return expect(remittance.createRemittance(
                puzzle,
                10,
                {from: aliceAccount, value:3000}
            )).to.be.rejected;
        });

        it("Should not have a balance after withdrawal", async function () {
            await remittance.releaseFunds(rPuzzle, {from: converter});
            const remittances = await remittance.remittances(puzzle);
            return assert.strictEqual(remittances.amount.toString(), '0');
        });

        it("Should be possible for the owner to withdraw any collected fees", async function () {
            const puzzleSec = await remittance.generatePuzzle(converter, rPuzzleSec, {from: aliceAccount})
            await remittance.createRemittance(puzzleSec, 10, {from: aliceAccount, value:5000});

            const expectedBalance = new BN(await web3.eth.getBalance(aliceAccount)).add(new BN(4000));

            const trx = await remittance.withdrawFees({from: aliceAccount});
            const trxTx = await web3.eth.getTransaction(trx.tx);

            let gasUsed = new BN(trx.receipt.gasUsed);
            const gasPrice = new BN(trxTx.gasPrice);
            const gasCost = gasPrice.mul(gasUsed);

            const aliceBalance = new BN(await web3.eth.getBalance(aliceAccount)).add(gasCost);

            return assert.strictEqual(aliceBalance.toString(), expectedBalance.toString());
        });
    });

    describe('deadline', function (){
        function timeout(ms) {
            return new Promise(resolve => setTimeout(resolve, ms));
        }

        it("Should not be possible to withdraw after the deadline has passed", async function () {
            await timeMachine.advanceTimeAndBlock(11);
            //return expect(remittance.releaseFunds(rPuzzle, {from: converter})).to.be.rejected;
            return await truffleAssert.fails(
                remittance.releaseFunds(rPuzzle, {from: converter}),
                truffleAssert.ErrorType.REVERT,
                "Remittance has lapsed"
            );
        });

        it("Should be possible for the sender to reclaim the deposited ehter after \
        the deadline has expired", async function () {
            await timeMachine.advanceTimeAndBlock(11);
            return expect(remittance.reclaimFunds(puzzle, {from: aliceAccount})).to.be.fulfilled;
        });

        it("Should send the reclaimed ether to the senders account", async function () {
            await timeMachine.advanceTimeAndBlock(11);
            const expectedBalance = new BN(await web3.eth.getBalance(aliceAccount)).add(new BN(3000));

            const trx = await remittance.reclaimFunds(puzzle, {from: aliceAccount});
            const trxTx = await web3.eth.getTransaction(trx.tx);

            let gasUsed = new BN(trx.receipt.gasUsed);
            const gasPrice = new BN(trxTx.gasPrice);
            const gasCost = gasPrice.mul(gasUsed);

            const aliceBalance = new BN(await web3.eth.getBalance(aliceAccount)).add(gasCost);
            return assert.strictEqual(aliceBalance.toString(), expectedBalance.toString());
        });

        it("Should not be possible for the owner to reclaim the deposited ehter before \
        the deadline has expired", async function () {
            return await truffleAssert.fails(
                remittance.reclaimFunds(puzzle, {from: aliceAccount}),
                truffleAssert.ErrorType.REVERT,
                "Remittance needs to expire"
            );
        });

        it("Should be possible to withdraw within the given deadline", async function () {
            return expect(remittance.releaseFunds(rPuzzle, {from: converter})).to.be.fulfilled;
        });
    });
});
