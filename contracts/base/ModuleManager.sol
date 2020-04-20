pragma solidity >=0.5.0 <0.7.0;
import "../common/Enum.sol";
import "../common/SelfAuthorized.sol";
import "./Executor.sol";
import "./Module.sol";


contract ModuleManagerStorage {
    address internal constant SENTINEL_MODULES = address(0x1);

    mapping (address => address) internal modules;
}


/// @title Module Manager - A contract that manages modules that can execute transactions via this contract
/// @author Stefan George - <stefan@gnosis.pm>
/// @author Richard Meissner - <richard@gnosis.pm>
contract ModuleManager is SelfAuthorized, Executor, ModuleManagerStorage {

    event EnabledModule(Module module);
    event DisabledModule(Module module);
    event ExecutionFromModuleSuccess(address indexed module);
    event ExecutionFromModuleFailure(address indexed module);

    function setupModules()
        internal
    {
        require(modules[SENTINEL_MODULES] == address(0), "Modules have already been initialized");
        modules[SENTINEL_MODULES] = SENTINEL_MODULES;
    }

    /// @dev Allows to add a module to the whitelist.
    ///      This can only be done via a Safe transaction.
    /// @param module Module to be whitelisted.
    function enableModule(Module module)
        public
        authorized
    {
        // Module address cannot be null or sentinel.
        require(address(module) != address(0) && address(module) != SENTINEL_MODULES, "Invalid module address provided");
        // Module cannot be added twice.
        require(modules[address(module)] == address(0), "Module has already been added");
        modules[address(module)] = modules[SENTINEL_MODULES];
        modules[SENTINEL_MODULES] = address(module);
        emit EnabledModule(module);
    }

    /// @dev Allows to remove a module from the whitelist.
    ///      This can only be done via a Safe transaction.
    /// @param prevModule Module that pointed to the module to be removed in the linked list
    /// @param module Module to be removed.
    function disableModule(Module prevModule, Module module)
        public
        authorized
    {
        // Validate module address and check that it corresponds to module index.
        require(address(module) != address(0) && address(module) != SENTINEL_MODULES, "Invalid module address provided");
        require(modules[address(prevModule)] == address(module), "Invalid prevModule, module pair provided");
        modules[address(prevModule)] = modules[address(module)];
        modules[address(module)] = address(0);
        emit DisabledModule(module);
    }

    /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Enum.Operation operation)
        public
        returns (bool success)
    {
        // Only whitelisted modules are allowed.
        require(msg.sender != SENTINEL_MODULES && modules[msg.sender] != address(0), "Method can only be called from an enabled module");
        // Execute transaction without further confirmations.
        success = execute(to, value, data, operation, gasleft());
        if (success) emit ExecutionFromModuleSuccess(msg.sender);
        else emit ExecutionFromModuleFailure(msg.sender);
    }

    /// @dev Allows a Module to execute a Safe transaction without any further confirmations and return data
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Enum.Operation operation)
        public
        returns (bool success, bytes memory returnData)
    {
        success = execTransactionFromModule(to, value, data, operation);
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            // Load free memory location
            let ptr := mload(0x40)
            // We allocate memory for the return data by setting the free memory location to
            // current free memory location + data size + 32 bytes for data size value
            mstore(0x40, add(ptr, add(returndatasize(), 0x20)))
            // Store the size
            mstore(ptr, returndatasize())
            // Store the data
            returndatacopy(add(ptr, 0x20), 0, returndatasize())
            // Point the return data to the correct memory location
            returnData := ptr
        }
    }
}
