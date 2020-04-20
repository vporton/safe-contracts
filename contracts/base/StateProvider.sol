pragma solidity >=0.5.0 <0.7.0;

/// @title Fallback Manager - A contract that manages fallback calls made to this contract
/// @author Richard Meissner - <richard@gnosis.pm>
contract StateProvider {

    /// @dev Will use reader contract to access state of the contract. The call will always revert, but still return the data.
    /// @param reader Address of the reader contract.
    /// @param readerData Data that should be sent to the reader contract.
    function requestState(address reader, bytes memory readerData) public returns(bytes memory) {
        address stateReader = reader == address(0) ? getStateReader() : reader;
        // solium-disable-next-line security/no-low-level-calls
        (,bytes memory response) = stateReader.delegatecall(readerData);
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            revert(add(response, 0x20), mload(response))
        }
    }

    function getStateReader() public view returns(address reader);
}