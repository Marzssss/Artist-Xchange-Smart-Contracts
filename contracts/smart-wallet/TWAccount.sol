// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

// Base
import "./utils/BaseAccount.sol";

// Extensions
import "../extension/Multicall.sol";
import "../dynamic-contracts/extension/Initializable.sol";
import "../dynamic-contracts/extension/PermissionsEnumerable.sol";
import "../dynamic-contracts/extension/ContractMetadata.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

// Utils
import "../openzeppelin-presets/utils/cryptography/ECDSA.sol";

library TWAccountStorage {
    bytes32 internal constant TWACCOUNT_STORAGE_POSITION = keccak256("twaccount.storage");

    struct Data {
        uint256 nonce;
    }

    function accountStorage() internal pure returns (Data storage twaccountData) {
        bytes32 position = TWACCOUNT_STORAGE_POSITION;
        assembly {
            twaccountData.slot := position
        }
    }
}

contract TWAccount is
    Initializable,
    Multicall,
    BaseAccount,
    ContractMetadata,
    PermissionsEnumerable,
    ERC721Holder,
    ERC1155Holder
{
    using ECDSA for bytes32;

    /*///////////////////////////////////////////////////////////////
                        State (constant, immutable)
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /// @notice EIP 4337 Entrypoint contract.
    IEntryPoint private immutable entrypointContract;

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    receive() external payable virtual {}

    constructor(IEntryPoint _entrypoint) {
        entrypointContract = _entrypoint;
    }

    /// @notice Initializes the smart contract walelt.
    function initialize(address _defaultAdmin) public virtual initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
    }

    /// @notice Checks whether the caller is the EntryPoint contract or the admin.
    modifier onlyAdminOrEntrypoint() {
        require(
            msg.sender == address(entryPoint()) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "TWAccount: not admin or EntryPoint."
        );
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Receiver) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Returns the nonce of the account.
    function nonce() public view virtual override returns (uint256) {
        TWAccountStorage.Data storage twaccountData = TWAccountStorage.accountStorage();
        return twaccountData.nonce;
    }

    /// @notice Returns the EIP 4337 entrypoint contract.
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return entrypointContract;
    }

    /// @notice Returns the balance of the account in Entrypoint.
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /// @notice Returns whether a signer is authorized to perform transactions using the wallet.
    function isValidSigner(address _signer) public view virtual returns (bool) {
        return hasRole(SIGNER_ROLE, _signer) || hasRole(DEFAULT_ADMIN_ROLE, _signer);
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a transaction (called directly from an admin, or by entryPoint)
    function execute(
        address _target,
        uint256 _value,
        bytes calldata _calldata
    ) external virtual onlyAdminOrEntrypoint {
        _call(_target, _value, _calldata);
    }

    /// @notice Executes a sequence transaction (called directly from an admin, or by entryPoint)
    function executeBatch(
        address[] calldata _target,
        uint256[] calldata _value,
        bytes[] calldata _calldata
    ) external virtual onlyAdminOrEntrypoint {
        require(
            _target.length == _calldata.length && _target.length == _value.length,
            "TWAccount: wrong array lengths."
        );
        for (uint256 i = 0; i < _target.length; i++) {
            _call(_target[i], _value[i], _calldata[i]);
        }
    }

    /// @notice Deposit funds for this account in Entrypoint.
    function addDeposit() public payable {
        entryPoint().depositTo{ value: msg.value }(address(this));
    }

    /// @notice Withdraw funds for this account from Entrypoint.
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Calls a target contract and reverts if it fails.
    function _call(
        address _target,
        uint256 value,
        bytes memory _calldata
    ) internal {
        (bool success, bytes memory result) = _target.call{ value: value }(_calldata);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Validates the nonce of a user operation and updates account nonce.
    function _validateAndUpdateNonce(UserOperation calldata userOp) internal override {
        TWAccountStorage.Data storage data = TWAccountStorage.accountStorage();
        require(data.nonce == userOp.nonce, "TWAccount: invalid nonce");

        data.nonce += 1;
    }

    /// @notice Validates the signature of a user operation.
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address signer = hash.recover(userOp.signature);

        if (!isValidSigner(signer)) return SIG_VALIDATION_FAILED;
        return 0;
    }

    /// @dev Returns whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view virtual override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
