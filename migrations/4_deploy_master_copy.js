var GnosisSafe = artifacts.require("./GnosisSafe.sol");
var GnosisSafeStateReader = artifacts.require("./GnosisSafeStateReader.sol");


const notOwnedAddress = "0x0000000000000000000000000000000000000002"
const notOwnedAddress2 = "0x0000000000000000000000000000000000000003"

module.exports = function(deployer) {
    deployer.deploy(GnosisSafe, GnosisSafeStateReader.address).then(function (safe) {
        return safe
    });    
};
