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
    const [aliceAccount, bobAccount, carolAccount] = accounts;

    let converter = carolAccount;
    let recipient = bobAccount;
    let cPuzzle = web3.utils.asciiToHex(process.env.PUZZLE_CONVERTER);
    let rPuzzle = web3.utils.asciiToHex(process.env.PUZZLE_RECIPIENT);

    beforeEach('Setup new Remittance before each test', async function () {
        Rem = await Remittance.new(converter, recipient, cPuzzle, rPuzzle, {from: aliceAccount, value:5000});
    });

    describe('deployment', function () {

        it("Should have the deployer as its owner and be in the created state", async function () {
            return expect(await Rem.getOwner()).to.equal(aliceAccount)
        });

        it("Should have a puzzle associate with an account and an amount of eth", async function () {
            puzzle = await Rem.generatePuzzle(cPuzzle, rPuzzle);
            balance = await Rem.balance(puzzle, converter);
            return assert.strictEqual(balance.toString(), '5000');
        });
    });

    describe('remittance', function (){

        it("Should not be possible to release the Remittance" +
            "without the right puzzle or right wrong account", async function () {
            expect(Rem.releaseFunds(
                web3.utils.asciiToHex('wrong puzzle'),
                rPuzzle,
                {from: converter}
            )).to.be.rejected;
            return expect(Rem.releaseFunds(cPuzzle, rPuzzle, {from: aliceAccount})).to.be.rejected;
        });


        it("Should be possible to release the remittance with the correct puzzle", async function () {
            return expect(Rem.releaseFunds(cPuzzle, rPuzzle, {from: converter})).to.be.fulfilled;
        });

        it("Should not be possible to relase the Remittance after its been released", async function () {
            Rem.releaseFunds(cPuzzle, rPuzzle, {from: converter});
            return expect(Rem.releaseFunds(cPuzzle, rPuzzle, {from: converter})).to.be.rejected;
        });

        it("Should send all the ether stored in the remittance to the converter after release", async function () {

            const originalBalance= await web3.eth.getBalance(converter);

            const trx = await Rem.releaseFunds(cPuzzle, rPuzzle, {from: converter});
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
                cPuzzle, rPuzzle, {from: converter}
            ).then(
                tx => logFR = tx.logs[0]
            );

            assert(logFR.args.sender, converter);
            assert(logFR.args.amount, 5000);
        });
    });
});
