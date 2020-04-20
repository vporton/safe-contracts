var MultiSend = artifacts.require("./MultiSend.sol");
var GnosisSafeStateReader = artifacts.require("./GnosisSafeStateReader.sol");

module.exports = function(deployer) {
    deployer.deploy(MultiSend);
    deployer.deploy(GnosisSafeStateReader);
};
