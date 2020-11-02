const utils = require('./utils/general')
const ethUtil = require('ethereumjs-util')
const abi = require('ethereumjs-abi')

const GnosisSafe = artifacts.require("./GnosisSafe.sol")
const TestReader = artifacts.require("./TestReader.sol")
const GnosisSafeStateReader = artifacts.require("./GnosisSafeStateReader.sol")
const ProxyFactory = artifacts.require("./GnosisSafeProxyFactory.sol")

contract('Gas Estimation', function(accounts) {

    it.only('should be able to read state', async () => {
        // Create lightwallet
        let lw = await utils.createLightwallet()
        // Create Master Copies
        let proxyFactory = await ProxyFactory.deployed()
        let gnosisSafeMasterCopy = await GnosisSafe.deployed()
        // Create Gnosis Safe
        let gnosisSafeData = await gnosisSafeMasterCopy.contract.methods.setup(
            [lw.accounts[0], lw.accounts[1], lw.accounts[2]], 2, utils.Address0, "0x", utils.Address0
        ).encodeABI()
        let gnosisSafe = await utils.getParamFromTxEvent(
            await proxyFactory.createProxy(gnosisSafeMasterCopy.address, gnosisSafeData),
            'ProxyCreation', 'proxy', proxyFactory.address, GnosisSafe, 'create Gnosis Safe Proxy',
        )

        let gnosisSafeStateReader = await GnosisSafeStateReader.deployed()
        const resp = await gnosisSafe.contract.methods.simulateDelegatecall(
            gnosisSafeStateReader.address, 
            gnosisSafeStateReader.contract.methods.getOwners().encodeABI()
        ).call()
        console.log({resp})
        console.log(web3.eth.abi.decodeParameters(["address[]"], resp))
        console.log([lw.accounts[0], lw.accounts[1], lw.accounts[2]])

        console.log(gnosisSafeStateReader.address)
        console.log(await gnosisSafe.getStateReader())
        const testReader = await TestReader.new()
        const resp3 = await gnosisSafe.contract.methods.simulateDelegatecall(
            utils.Address0, 
            gnosisSafeStateReader.contract.methods.isOwner(lw.accounts[0]).encodeABI()
        ).call()
        console.log({resp3})
        const resp4 = await gnosisSafe.contract.methods.simulateDelegatecall(
            gnosisSafeStateReader.address, 
            gnosisSafeStateReader.contract.methods.isOwner(lw.accounts[0]).encodeABI()
        ).call()
        console.log({resp4})
        const resp2 = await web3.eth.call({
            to: testReader.address, 
            data: await testReader.contract.methods.checkOwner(gnosisSafe.address, lw.accounts[0]).encodeABI()
        })
        console.log({resp2})
        console.log(await testReader.checkOwner.call(gnosisSafe.address, lw.accounts[0]))
    })
})
