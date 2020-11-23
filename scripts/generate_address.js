
const ethUtil = require('ethereumjs-util')
const abi = require('ethereumjs-abi')
const Address0 = "0x".padEnd(42, '0')
const assert = require('assert')


let getCreationData = async function() {

    const Proxy = artifacts.require("./GnosisSafeProxy.sol")
    const GnosisSafe = artifacts.require("./GnosisSafe.sol")
    const ProxyFactory = artifacts.require("./GnosisSafeProxyFactory.sol")


    const gasPrice = await web3.utils.toWei('75', 'gwei')

    console.log("gasPrice: ", gasPrice)

    let proxyFactory = await ProxyFactory.at("0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B")
    let gnosisSafeMasterCopy = await GnosisSafe.at("0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F")
    
    gnosisSafeData = await gnosisSafeMasterCopy.contract.methods.setup(
        [
            "0xE4Df0cdC9eF7e388eA906226010bBD1B9A6fFeD9", 
            "0xA1cf7F847eCD82459ce05a218EaA38a9D92E7b6b",
            "0xD68f1A882f3F9ffddaBd4D30c4F8Dfca1f9e51Ba",
            "0xFcf00B0fEdBc8f2F35a3B8d4B858d5805f2Bb05D",
            "0x8fd960F1B9D68BAD2B97bD232FB75CC1f186B064"
        ],
         3, Address0, "0x", Address0, Address0, 0, Address0
    ).encodeABI()

    let proxyCreationCode = await proxyFactory.proxyCreationCode()
    
    // assert.equal(proxyCreationCode, Proxy.bytecode)
    let constructorData = abi.rawEncode(
        ['address'],
        [ gnosisSafeMasterCopy.address ]
    ).toString('hex')
    

    //Loop until generated address has the value we want
    let target = Address0
    //let nonce = 470000000
    let nonce = 4202185806
    while(target[2] != "0"  || target[3] != "d" || target[4] != "a" || target[5] != "0" || target[38] != "5" || target[39] != "a" || target[40] != "f" || target[41] != "e"){
        if((nonce%1000000) == 0){
            console.log("Attempt nonce: ", nonce, " safe: ", target)
        }
        let encodedNonce = abi.rawEncode(['uint256'], [nonce]).toString('hex')
        target = "0x" + ethUtil.generateAddress2(proxyFactory.address, ethUtil.keccak256("0x" + ethUtil.keccak256(gnosisSafeData).toString("hex") + encodedNonce), proxyCreationCode + constructorData).toString("hex")
        nonce++
    }
    
    console.log("    Predicted safe address: " + target)
    assert.equal(await web3.eth.getCode(target), "0x")
    return {
        safe: target,
        data: gnosisSafeData,
        gasToken: Address0,
        userCosts: 0,
        gasPrice: gasPrice,
        creationNonce: nonce
    }
}

process = async () => {
    

    const txDetails = await getCreationData()

    console.log(JSON.stringify(txDetails, null, 4));
}

module.exports = function (callback) {
    process()
        .then(() => { callback() })
        .catch((err) => { callback(err) })
}
