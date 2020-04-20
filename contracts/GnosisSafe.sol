pragma solidity >=0.5.0 <0.7.0;
import "./base/ModuleManager.sol";
import "./base/OwnerManager.sol";
import "./base/FallbackManager.sol";
import "./base/StateProvider.sol";
import "./common/MasterCopy.sol";
import "./common/SignatureDecoder.sol";
import "./common/SecuredTokenTransfer.sol";
import "./interfaces/ISignatureValidator.sol";
import "./external/GnosisSafeMath.sol";

contract GnosisSafeStorage {
    uint256 public nextBucket;
    address _unused_; // We keep this here to not change the storage layout (previously domainSeparator)
    // Mapping to keep track of all message hashes that have been approve by ALL REQUIRED owners
    mapping(bytes32 => uint256) public signedMessages;
    // Mapping to keep track of all hashes (message or transaction) that have been approve by ANY owners
    mapping(address => mapping(bytes32 => uint256)) public approvedHashes;
    address stateReader;
    mapping(uint256 => uint256) public buckets;
}

/// @title Gnosis Safe - A multisignature wallet with support for confirmations using signed messages based on ERC191.
/// @author Stefan George - <stefan@gnosis.io>
/// @author Richard Meissner - <richard@gnosis.io>
/// @author Ricardo Guilherme Schmidt - (Status Research & Development GmbH) - Gas Token Payment
contract GnosisSafe
    is MasterCopy, ModuleManager, OwnerManager, SignatureDecoder, SecuredTokenTransfer, ISignatureValidatorConstants, FallbackManager, GnosisSafeStorage, StateProvider {

    using GnosisSafeMath for uint256;

    string public constant NAME = "Gnosis Safe";
    string public constant VERSION = "1.1.1";

    //keccak256(
    //    "EIP712Domain(address verifyingContract,uint256 chainId)"
    //);
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH = 0xa1f4e2f207746c24e01c8e10e467322f5fea4cccab3cd2f1c95d700b6a0c218b;

    //keccak256(
    //    "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 nonce)"
    //);
    bytes32 private constant SAFE_TX_TYPEHASH = 0x132cda0c935904cd74514d72e79dd4e1517ae3dad9a49b196ce701fc515fc181;

    //keccak256(
    //    "SafeMessage(bytes message)"
    //);
    bytes32 private constant SAFE_MSG_TYPEHASH = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

    uint256 constant BUCKET_SIZE = 256;
    uint256 constant MAX_BUCKET_VALUE = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    event ApproveHash(
        bytes32 indexed approvedHash,
        address indexed owner
    );
    event SignMsg(
        bytes32 indexed msgHash
    );
    event ExecutionFailure(
        bytes32 txHash
    );
    event ExecutionSuccess(
        bytes32 txHash
    );

    // This constructor ensures that this contract can only be used as a master copy for Proxy contracts
    constructor(address _stateReader) public {
        // By setting the threshold it is not possible to call setup anymore,
        // so we create a Safe with 0 owners and threshold 1.
        // This is an unusable Safe, perfect for the mastercopy
        threshold = 1;
        stateReader = _stateReader;
    }

    function getStateReader() public view returns(address reader) {
        address payable master = address(uint(masterCopy));
        reader = master == address(0) ? stateReader : GnosisSafe(master).getStateReader();
    }

    /// @dev Setup function sets initial storage of contract.
    /// @param _owners List of Safe owners.
    /// @param _threshold Number of required confirmations for a Safe transaction.
    /// @param to Contract address for optional delegate call.
    /// @param data Data payload for optional delegate call.
    /// @param fallbackHandler Handler for fallback calls to this contract
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler
    )
        external
    {
        setupOwners(_owners, _threshold);
        if (fallbackHandler != address(0)) internalSetFallbackHandler(fallbackHandler);
        // As setupOwners can only be called if the contract has not been initialized we don't need a check for setupModules
        setupModules();
        if (to != address(0))
            // Setup has to complete successfully or transaction fails.
            require(executeDelegateCall(to, data, gasleft()), "Could not finish initialization");
    }

    /// @dev Allows to execute a Safe transaction confirmed by required number of owners and then pays the account that submitted the transaction.
    ///      Note: The fees are always transfered, even if the user transaction fails.
    /// @param to Destination address of Safe transaction.
    /// @param value Ether value of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    /// @param safeTxGas Gas that should be used for the Safe transaction.
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint nonce,
        bytes calldata signatures
    )
        external
        returns (bool success)
    {
        bytes32 txHash;
        // Use scope here to limit variable lifetime and prevent `stack too deep` errors
        {
            bytes memory txHashData = encodeTransactionData(
                to, value, data, operation, // Transaction info
                safeTxGas, nonce
            );
            // Increase nonce and execute transaction.
            checkNonce(nonce);
            txHash = keccak256(txHashData);
            checkSignaturesInternal(txHash, txHashData, signatures, true);
        }
        require(gasleft() >= safeTxGas, "Not enough gas to execute safe transaction");
        // Use scope here to limit variable lifetime and prevent `stack too deep` errors
        {
            success = execute(to, value, data, operation, gasleft());
            if(success)
                emit ExecutionSuccess(txHash);
            else
                emit ExecutionFailure(txHash);
        }
    }

    function checkNonce(uint256 nonce) internal {
        uint256 bucket = nonce / BUCKET_SIZE;
        uint256 next = nextBucket;
        require(bucket >= next, "Nonce too small");
        uint256 buckedMask = 1 << nonce % BUCKET_SIZE;
        uint256 buckedValue = buckets[bucket];
        require((buckets[bucket] & buckedMask) == 0, "Nonce alread used");
        buckedValue = buckedValue | buckedMask;
        if (next == bucket && buckedValue == MAX_BUCKET_VALUE) {
            nextBucket = bucket + 1;
            buckets[bucket] = 0;
        } else {
            buckets[bucket] = buckedValue;
        }
    }

    /**
    * @dev Checks whether the signature provided is valid for the provided data, hash. Will revert otherwise.
    * @param dataHash Hash of the data (could be either a message hash or transaction hash)
    * @param data That should be signed (this is passed to an external validator contract)
    * @param signatures Signature data that should be verified. Can be ECDSA signature, contract signature (EIP-1271) or approved hash.
    */
    function checkSignatures(bytes32 dataHash, bytes memory data, bytes memory signatures) public {
        checkSignaturesInternal(dataHash, data, signatures, false);
    }

    /**
    * @dev Checks whether the signature provided is valid for the provided data, hash. Will revert otherwise.
    * @param dataHash Hash of the data (could be either a message hash or transaction hash)
    * @param data That should be signed (this is passed to an external validator contract)
    * @param signatures Signature data that should be verified. Can be ECDSA signature, contract signature (EIP-1271) or approved hash.
    * @param consumeHash Indicates that in case of an approved hash the storage can be freed to save gas
    */
    // TODO return list of consumed hashes to make it view
    function checkSignaturesInternal(bytes32 dataHash, bytes memory data, bytes memory signatures, bool consumeHash)
        internal
    {
        // Load threshold to avoid multiple storage loads
        uint256 _threshold = threshold;
        // Check that a threshold is set
        require(_threshold > 0, "Threshold needs to be defined!");
        // Check that the provided signature data is not too short
        require(signatures.length >= _threshold.mul(65), "Signatures data too short");
        // There cannot be an owner with address 0.
        address lastOwner = address(0);
        address currentOwner;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 i;
        for (i = 0; i < _threshold; i++) {
            (v, r, s) = signatureSplit(signatures, i);
            // If v is 0 then it is a contract signature
            if (v == 0) {
                // When handling contract signatures the address of the contract is encoded into r
                currentOwner = address(uint256(r));

                // Check that signature data pointer (s) is not pointing inside the static part of the signatures bytes
                // This check is not completely accurate, since it is possible that more signatures than the threshold are send.
                // Here we only check that the pointer is not pointing inside the part that is being processed
                require(uint256(s) >= _threshold.mul(65), "Invalid contract signature location: inside static part");

                // Check that signature data pointer (s) is in bounds (points to the length of data -> 32 bytes)
                require(uint256(s).add(32) <= signatures.length, "Invalid contract signature location: length not present");

                // Check if the contract signature is in bounds: start of data is s + 32 and end is start + signature length
                uint256 contractSignatureLen;
                // solium-disable-next-line security/no-inline-assembly
                assembly {
                    contractSignatureLen := mload(add(add(signatures, s), 0x20))
                }
                require(uint256(s).add(32).add(contractSignatureLen) <= signatures.length, "Invalid contract signature location: data not complete");

                // Check signature
                bytes memory contractSignature;
                // solium-disable-next-line security/no-inline-assembly
                assembly {
                    // The signature data for contract signatures is appended to the concatenated signatures and the offset is stored in s
                    contractSignature := add(add(signatures, s), 0x20)
                }
                require(ISignatureValidator(currentOwner).isValidSignature(data, contractSignature) == EIP1271_MAGIC_VALUE, "Invalid contract signature provided");
            // If v is 1 then it is an approved hash
            } else if (v == 1) {
                // When handling approved hashes the address of the approver is encoded into r
                currentOwner = address(uint256(r));
                // Hashes are automatically approved by the sender of the message or when they have been pre-approved via a separate transaction
                require(msg.sender == currentOwner || approvedHashes[currentOwner][dataHash] != 0, "Hash has not been approved");
                // Hash has been marked for consumption. If this hash was pre-approved free storage
                if (consumeHash && msg.sender != currentOwner) {
                    approvedHashes[currentOwner][dataHash] = 0;
                }
            } else if (v > 30) {
                // To support eth_sign and similar we adjust v and hash the messageHash with the Ethereum message prefix before applying ecrecover
                currentOwner = ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)), v - 4, r, s);
            } else {
                // Use ecrecover with the messageHash for EOA signatures
                currentOwner = ecrecover(dataHash, v, r, s);
            }
            require (
                currentOwner > lastOwner && owners[currentOwner] != address(0) && currentOwner != SENTINEL_OWNERS,
                "Invalid owner provided"
            );
            lastOwner = currentOwner;
        }
    }

    /**
    * @dev Marks a hash as approved. This can be used to validate a hash that is used by a signature.
    * @param hashToApprove The hash that should be marked as approved for signatures that are verified by this contract.
    */
    function approveHash(bytes32 hashToApprove)
        external
    {
        require(owners[msg.sender] != address(0), "Only owners can approve a hash");
        approvedHashes[msg.sender][hashToApprove] = 1;
        emit ApproveHash(hashToApprove, msg.sender);
    }

    /**
    * @dev Marks a message as signed
    * @param _data Arbitrary length data that should be marked as signed on the behalf of address(this)
    */
    function signMessage(bytes calldata _data)
        external
        authorized
    {
        bytes32 msgHash = getMessageHash(_data);
        signedMessages[msgHash] = 1;
        emit SignMsg(msgHash);
    }

    /**
    * Implementation of ISignatureValidator (see `interfaces/ISignatureValidator.sol`)
    * @dev Should return whether the signature provided is valid for the provided data.
    *       The save does not implement the interface since `checkSignatures` is not a view method.
    *       The method will not perform any state changes (see parameters of `checkSignatures`)
    * @param _data Arbitrary length data signed on the behalf of address(this)
    * @param _signature Signature byte array associated with _data
    * @return a bool upon valid or invalid signature with corresponding _data
    */
    function isValidSignature(bytes calldata _data, bytes calldata _signature)
        external
        returns (bytes4)
    {
        bytes32 messageHash = getMessageHash(_data);
        if (_signature.length == 0) {
            require(signedMessages[messageHash] != 0, "Hash not approved");
        } else {
            // consumeHash needs to be false, as the state should not be changed
            checkSignaturesInternal(messageHash, _data, _signature, false);
        }
        return EIP1271_MAGIC_VALUE;
    }

    function getChainId() private pure returns(uint chainId) {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            chainId := chainid()
        }
    }

    /// @dev Returns hash of a message that can be signed by owners.
    /// @param message Message that should be hashed
    /// @return Message hash.
    function getMessageHash(
        bytes memory message
    )
        public
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, this, getChainId()));
        bytes32 safeMessageHash = keccak256(
            abi.encode(SAFE_MSG_TYPEHASH, keccak256(message))
        );
        return keccak256(
            abi.encodePacked(byte(0x19), byte(0x01), domainSeparator, safeMessageHash)
        );
    }

    /// @dev Returns the bytes that are hashed to be signed by owners.
    /// @param to Destination address.
    /// @param value Ether value.
    /// @param data Data payload.
    /// @param operation Operation type.
    /// @param safeTxGas Fas that should be used for the safe transaction.
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash bytes.
    function encodeTransactionData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 _nonce
    )
        public
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, this, getChainId()));
        bytes32 safeTxHash = keccak256(
            abi.encode(SAFE_TX_TYPEHASH, to, value, keccak256(data), operation, safeTxGas, _nonce)
        );
        return abi.encodePacked(byte(0x19), byte(0x01), domainSeparator, safeTxHash);
    }

    /// @dev Returns hash to be signed by owners.
    /// @param to Destination address.
    /// @param value Ether value.
    /// @param data Data payload.
    /// @param operation Operation type.
    /// @param safeTxGas Fas that should be used for the safe transaction.
    /// @param _nonce Transaction nonce.
    /// @return Transaction hash.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 _nonce
    )
        public
        view
        returns (bytes32)
    {
        return keccak256(encodeTransactionData(to, value, data, operation, safeTxGas, _nonce));
    }
}
