var Remittance = artifacts.require("./Remittance.sol");

require("dotenv").config({path: "./.env"});

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(Remittance, false, 2000, {from: accounts[0]});
};
