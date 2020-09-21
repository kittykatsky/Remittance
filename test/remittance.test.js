/* xxx
 *
 * Tests for xxx contract.
 * All test refers to the xxx contract (it)
 * unless otherwise specifed.
 *
 * tests require min. 3 accounts
 *
 * */

const BN = web3.utils.BN;
const chai = require('chai');
var chaiAsPromised = require("chai-as-promised");
chai.use(chaiAsPromised);
const expect = chai.expect;
const truffleAssert = require('truffle-assertions');
const Remittance = artifacts.require('Remittance');

require("dotenv").config({path: "./.env"});

contract('Remittance', function(accounts) {

    let Rem;
    let puzzle;
    const [aliceAccount, bobAccount, carolAccount] = accounts;

    let converter = carolAccount;
    let recipient = bobAccount;
    let rPuzzle = web3.utils.fromAscii(process.env.PUZZLE_RECIPIENT);
    let rPuzzleSec = web3.utils.fromAscii(process.env.PUZZLE_RECIPIENT_SECONDARY);


    beforeEach('Setup new Remittance before each test', async function () {
        Rem = await Remittance.new(false, {from: aliceAccount});
        puzzle = await Rem.generatePuzzle(converter, rPuzzle, {from: aliceAccount})
        await Rem.createRemittance(converter, puzzle, 10, {from: aliceAccount, value:5000});
    });

    describe('deployment', function () {

        it("Should have the deployer as its owner and be in the created state", async function () {
            return expect(await Rem.getOwner()).to.equal(aliceAccount)
        });

        it("Should have a puzzle associate with a struct holding sender, \
        amount and deadline", async function () {
            remittances = await Rem.remittances(puzzle);

            const latestBlock = await web3.eth.getBlockNumber()
            const block = await web3.eth.getBlock(latestBlock)
            const setDeadline = block.timestamp + 10
            assert.strictEqual(remittances.from, aliceAccount);
            assert.strictEqual(remittances.deadline.toString(), setDeadline.toString());
            return assert.strictEqual(remittances.amount.toString(), '5000');
        });

        it("Should not be possible to generate the same secret from two seperte contracts", async function () {
            Rem2 = await Remittance.new(false, {from: aliceAccount});
            assert.notEqual(
                Rem.generatePuzzle(converter, rPuzzle, {from: aliceAccount}),
                Rem2.generatePuzzle(converter, rPuzzle, {from: aliceAccount})
            )
        })
    });

    describe('Pausable', function () {

        it("Should be owned by the deployer", async function () {
            return expect(await Rem.getOwner()).to.equal(aliceAccount)
        });

        it("Should not be possible to withdraw when paused", async function () {
            await Rem.pause({from: aliceAccount})
            return expect(Rem.releaseFunds(puzzle, {from: converter})).to.be.rejected;
        });

        it("Should be possible to kill a paused contract", async function () {
            await Rem.pause({from: aliceAccount});
            const tx = await Rem.kill({from: aliceAccount});
            return assert.strictEqual(tx.receipt.status, true);
        });

        it("Should no be possible to run a killed contract", async function () {
            await Rem.pause({from: aliceAccount});
            return expect(Rem.releaseFunds(puzzle, {from: converter})).to.be.rejected;
        });

        it("Should not be possible to unpause a killed contract", async function () {
            await Rem.pause({from: aliceAccount});
            await Rem.kill({from: aliceAccount});
            return expect(Rem.resume({from: aliceAccount})).to.be.rejected;
        });

        it("Should not be possible to empty a live contract", async function () {
            return expect(Rem.emptyAccount(aliceAccount, {from: aliceAccount})).to.be.rejected;
        });

        it("Should be possible to empty a killed contract", async function () {
            await Rem.pause({from: aliceAccount});
            await Rem.kill({from: aliceAccount});
            return expect(Rem.emptyAccount(aliceAccount, {from: aliceAccount})).to.be.fulfilled;
        });
    });

    describe('remittance', function (){

        it("Should not be possible to release the Remittance" +
            "without the right puzzle or right wrong account", async function () {
            const wrongPuzzle = Rem.generatePuzzle(converter, rPuzzleSec, {from: aliceAccount})
            expect(Rem.releaseFunds(
                wrongPuzzle,
                {from: converter}
            )).to.be.rejected;
            return expect(Rem.releaseFunds(rPuzzle, {from: aliceAccount})).to.be.rejected;
        });


        it("Should be possible to release the remittance with the correct puzzle", async function () {
            return expect(Rem.releaseFunds(rPuzzle, {from: converter})).to.be.fulfilled;
        });

        it("Should not be possible to release the Remittance after its been released", async function () {
            Rem.releaseFunds(rPuzzle, {from: converter});
            return expect(Rem.releaseFunds(rPuzzle, {from: converter})).to.be.rejected;
        });

        it("Should send all the ether stored in the remittance to the converter after release", async function () {

            const originalBalance= await web3.eth.getBalance(converter);

            const trx = await Rem.releaseFunds(rPuzzle, {from: converter});
            const trxTx = await web3.eth.getTransaction(trx.tx);

            let gasUsed = new BN(trx.receipt.gasUsed);
            const gasPrice = new BN(trxTx.gasPrice);
            const gasCost = gasPrice.mul(gasUsed);

            const checkBalance = new BN(originalBalance).sub(gasCost);
            const converterBalance = new BN(await web3.eth.getBalance(converter));

            return assert.strictEqual(converterBalance.sub(checkBalance).toString(), '5000');
        });

        it("Should be possible for Alice to verify that the transaction went through", async function () {

            await Rem.releaseFunds(
                rPuzzle, {from: converter}
            ).then(
                tx => logFR = tx.logs[0]
            );

            assert(logFR.args.sender, converter);
            assert(logFR.args.amount.toString(), '5000');
        });

        it("It should be possible to create several remittances on the same contract", async function () {
            const newPuzzle = await Rem.generatePuzzle(converter, rPuzzleSec, {from: aliceAccount})
            return expect(Rem.createRemittance(
                converter,
                newPuzzle,
                10,
                {from: aliceAccount, value:5000}
            )).to.be.fulfilled;
        });

        it("It should not be possible to create a remittance with the same puzzle", async function () {
            return expect(Rem.createRemittance(
                converter,
                puzzle,
                10,
                {from: aliceAccount, value:5000}
            )).to.be.rejected;
        });

        it("It should not have a balance after withdrawal", async function () {
            await Rem.releaseFunds(rPuzzle, {from: converter});
            remittances = await Rem.remittances(puzzle);
            return assert.strictEqual(remittances.amount.toString(), '0');
        });
    });

    describe('deadline', function (){
        function timeout(ms) {
            return new Promise(resolve => setTimeout(resolve, ms));
        }

        it("Should not be possible to withdraw after the deadline has passed", async function () {
            await timeout(11000);
            return expect(Rem.releaseFunds(rPuzzle, {from: converter})).to.be.rejected;
        });

        it("Should be possible for the owner to reclaim the deposited ehter after \
        the deadline has expired", async function () {
            await timeout(11000);
            return expect(Rem.reclaimFunds(converter, rPuzzle, {from: aliceAccount})).to.be.fulfilled;
        });

        it("Should not be possible for the owner to reclaim the deposited ehter before \
        the deadline has expired", async function () {
            return expect(Rem.reclaimFunds(converter, rPuzzle, {from: aliceAccount})).to.be.rejected;
        });

        it("Should be possible to withdraw within the given deadline", async function () {
            return expect(Rem.releaseFunds(rPuzzle, {from: converter})).to.be.fulfilled;
        });
    });
});
