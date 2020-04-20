pragma solidity >=0.5.0 <0.7.0;
import "./OwnerManager.sol";
import "./ModuleManager.sol";
import "../GnosisSafe.sol";
import "../common/MasterCopy.sol";

contract GnosisSafeStateReader is MasterCopyStorage, ModuleManagerStorage, OwnerManagerStorage, GnosisSafeStorage {

    /// @dev Returns array of first 10 modules.
    /// @return Array of modules.
    function getModules()
        public
        view
        returns (address[] memory)
    {
        (address[] memory array,) = getModulesPaginated(SENTINEL_MODULES, 10);
        return array;
    }

    /// @dev Returns array of modules.
    /// @param start Start of the page.
    /// @param pageSize Maximum number of modules that should be returned.
    /// @return Array of modules.
    function getModulesPaginated(address start, uint256 pageSize)
        public
        view
        returns (address[] memory array, address next)
    {
        // Init array with max page size
        array = new address[](pageSize);

        // Populate return array
        uint256 moduleCount = 0;
        address currentModule = modules[start];
        while(currentModule != address(0x0) && currentModule != SENTINEL_MODULES && moduleCount < pageSize) {
            array[moduleCount] = currentModule;
            currentModule = modules[currentModule];
            moduleCount++;
        }
        next = currentModule;
        // Set correct size of returned array
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            mstore(array, moduleCount)
        }
    }

    function getThreshold() public view returns(uint) {
        return threshold;
    }

    function isOwner(address owner)
        public
        view
        returns (bool)
    {
        return owner != SENTINEL_OWNERS && owners[owner] != address(0);
    }

    /// @dev Returns array of owners.
    /// @return Array of Safe owners.
    function getOwners()
        public
        view
        returns (address[] memory)
    {
        address[] memory array = new address[](ownerCount);

        // populate return array
        uint256 index = 0;
        address currentOwner = owners[SENTINEL_OWNERS];
        while(currentOwner != SENTINEL_OWNERS) {
            array[index] = currentOwner;
            currentOwner = owners[currentOwner];
            index ++;
        }
        return array;
    }
}

library GnosisSafeReader {
    function checkOwner(GnosisSafe safe, address owner) internal view returns (bool isOwner) {
        bytes memory isOwnerRequest = abi.encodeWithSignature("isOwner(address)", owner);
        (,bytes memory isOwnerResponse) = address(safe).staticcall(
            abi.encodeWithSignature("requestState(address,bytes)", address(0), isOwnerRequest)
        );
        (isOwner) = abi.decode(isOwnerResponse, (bool));
    }
}