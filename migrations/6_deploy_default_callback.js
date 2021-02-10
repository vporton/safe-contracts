var DefaultCallbackHandler = artifacts.require("./DefaultCallbackHandler.sol");

module.exports = function(deployer) {
    deployer.deploy(DefaultCallbackHandler)
};
