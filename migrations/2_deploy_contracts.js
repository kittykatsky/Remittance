var Remittance = artifacts.require("./Remittance.sol");

require("dotenv").config({path: "./.env"});

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(Remittance, accounts[2], web3.utils.asciiToHex(process.env.PUZZLE_CONVERTER), web3.utils.asciiToHex(process.env.PUZZLE_RECIPIENT), 5000, false, {from: accounts[0], value:5000});
};
