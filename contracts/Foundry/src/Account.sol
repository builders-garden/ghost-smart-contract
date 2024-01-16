// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

// Base
import "@thirdweb/prebuilts/account/utils/BaseAccount.sol";

// Extensions
import "@thirdweb/prebuilts/account/utils/AccountCore.sol";
import "@thirdweb/extension/upgradeable/ContractMetadata.sol";
import "@thirdweb/external-deps/openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import "@thirdweb/external-deps/openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";

// Utils
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@thirdweb/eip/ERC1271.sol";
import "@thirdweb/prebuilts/account/utils/Helpers.sol";
import "@thirdweb/external-deps/openzeppelin/utils/cryptography/ECDSA.sol";
import "@thirdweb/prebuilts/account/utils/BaseAccountFactory.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

interface IPool {
    function getUserAccountData(
    address user
    ) external view
    returns (
      uint256 totalCollateralBase,
      uint256 totalDebtBase,
      uint256 availableBorrowsBase,
      uint256 currentLiquidationThreshold,
      uint256 ltv,
      uint256 healthFactor
    );
}


contract Account is AccountCore, ContractMetadata, ERC1271, ERC721Holder, ERC1155Holder {
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint public ghoTreshold;
    address public automationUpkeep;
    address public defaultToken = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60;
    address public uniswapRouter; // hardcode 
    bool public allowedSupply;
    
    bytes32 private constant MSG_TYPEHASH = keccak256("AccountMessage(bytes message)");

    /*///////////////////////////////////////////////////////////////
                    Constructor, Initializer, Modifiers
    //////////////////////////////////////////////////////////////*/

    constructor(IEntryPoint _entrypoint, address _factory) AccountCore(_entrypoint, _factory) {
        automationUpkeep = msg.sender;
        allowedSupply = true;
    }

    /// @notice Checks whether the caller is the EntryPoint contract or the admin.
    modifier onlyAdminOrEntrypoint() virtual {
        require(msg.sender == address(entryPoint()) || isAdmin(msg.sender), "Account: not admin or EntryPoint.");
        _;
    }

    /// @notice Checks whether the caller is the Chainlink Upkeep contract or the admin.
    modifier onlyAdminOrUpkeep virtual {
        require(msg.sender == automationUpkeep || isAdmin(msg.sender), "Account: not admin or Upkeep.");
        _;
    }


    /// @notice Lets the account receive native tokens.
    receive() external payable {}

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

    /// @notice See EIP-1271
    function isValidSignature(
        bytes32 _message,
        bytes memory _signature
    ) public view virtual override returns (bytes4 magicValue) {
        bytes32 messageHash = getMessageHash(abi.encode(_message));
        address signer = messageHash.recover(_signature);

        if (isAdmin(signer)) {
            return MAGICVALUE;
        }

        address caller = msg.sender;
        EnumerableSet.AddressSet storage approvedTargets = _accountPermissionsStorage().approvedTargets[signer];

        require(
            approvedTargets.contains(caller) || (approvedTargets.length() == 1 && approvedTargets.at(0) == address(0)),
            "Account: caller not approved target."
        );

        if (isActiveSigner(signer)) {
            magicValue = MAGICVALUE;
        }
    }

    /**
     * @notice Returns the hash of message that should be signed for EIP1271 verification.
     * @param message Message to be hashed i.e. `keccak256(abi.encode(data))`
     * @return Hashed message
     */
    function getMessageHash(bytes memory message) public view returns (bytes32) {
        bytes32 messageHash = keccak256(abi.encode(MSG_TYPEHASH, keccak256(message)));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), messageHash));
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a transaction (called directly from an admin, or by entryPoint)
    function execute(address _target, uint256 _value, bytes calldata _calldata) external virtual onlyAdminOrEntrypoint {
        _registerOnFactory();
        _call(_target, _value, _calldata);
    }

    /// @notice Executes a sequence transaction (called directly from an admin, or by entryPoint)
    function executeBatch(
        address[] calldata _target,
        uint256[] calldata _value,
        bytes[] calldata _calldata
    ) external virtual onlyAdminOrEntrypoint {
        _registerOnFactory();

        require(_target.length == _calldata.length && _target.length == _value.length, "Account: wrong array lengths.");
        for (uint256 i = 0; i < _target.length; i++) {
            _call(_target[i], _value[i], _calldata[i]);
        }
    }

    /// @notice Special function execution for ghost wallet. Execute a swap for defaultToken and supply on AAVE.
    function executeSwapAndSupply(
        address token,
        address aavePool // AAVE Pool address to supply token different from defaultToken aka GHO
    ) external virtual onlyAdminOrUpkeep {
        require(allowedSupply, "Account: supply paused.");
        _registerOnFactory();
        
        uint balance = IERC20(token).balanceOf(address(this));
        // Accounts works with 6 decimals tokens (DAI, USDC)
        uint256 supplyAmount = balance % 1e6;
        uint256 swapAmount = balance - supplyAmount;
        // Get AAVE v3 bottor debt to repay
        (, uint debt, , , ,) = IPool(aavePool).getUserAccountData(address(this));
        
        if (supplyAmount > 0) {
            // We expect debt is lower than supplyAmount
            if (debt > 0 && supplyAmount <= debt){
                bytes memory repay = abi.encodeWithSelector(0x573ade81, token, supplyAmount, 2, address(this));
                _call(aavePool, 0, repay);
            } else {
                // Supply token to AAVE
                IERC20(token).approve(aavePool, supplyAmount);
                bytes memory supplyData = abi.encodeWithSelector(0x617ba037, token, supplyAmount, address(this), 0);
                _call(aavePool, 0, supplyData);
            }
        }
        
        // Swap token on Uniswap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = defaultToken; //GHO
        bytes memory swapData = abi.encodeWithSelector(0x8803dbee, swapAmount, swapAmount, path, address(this), (block.timestamp+300));
        _call(uniswapRouter, 0, swapData);
    }

    function executeSupplyToVault() public onlyAdminOrUpkeep() {
        uint ghoBalance = IERC20(defaultToken).balanceOf(address(this));
        uint ghoToSupply = ghoBalance - ghoTreshold;
        // send the remainder to the vault
        ghoTreshold = ghoBalance - ghoToSupply;
    }

    /// @notice Deposit funds for this account in Entrypoint.
    function addDeposit() public payable {
        entryPoint().depositTo{ value: msg.value }(address(this));
    }

    /// @notice Withdraw funds for this account from Entrypoint.
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public {
        _onlyAdmin();
        entryPoint().withdrawTo(withdrawAddress, amount);
    }
    /*
    function setUpkeep(address _upkeep) external virtual onlyAdminOrEntrypoint() {
        automationUpkeep = _upkeep;
    }
    
    function setDefaultToken(address _defaultToken) external virtual onlyAdminOrEntrypoint() {
        defaultToken = _defaultToken;
    }

    function setUniswapRouter(address _uniswapRouter) external virtual onlyAdminOrEntrypoint() {
        uniswapRouter = _uniswapRouter;
    }
    */
    function setAllowedSupply(bool _allowedSupply) external virtual onlyAdminOrEntrypoint() {
        allowedSupply = _allowedSupply;
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Registers the account on the factory if it hasn't been registered yet.
    function _registerOnFactory() internal virtual {
        BaseAccountFactory factoryContract = BaseAccountFactory(factory);
        if (!factoryContract.isRegistered(address(this))) {
            factoryContract.onRegister(AccountCoreStorage.data().creationSalt);
        }
    }

    /// @dev Calls a target contract and reverts if it fails.
    function _call(
        address _target,
        uint256 value,
        bytes memory _calldata
    ) internal virtual returns (bytes memory result) {
        bool success;
        (success, result) = _target.call{ value: value }(_calldata);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @dev Returns whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view virtual override returns (bool) {
        return isAdmin(msg.sender) || msg.sender == address(this);
    }
}