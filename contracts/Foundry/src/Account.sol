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
import "../src/utils/IERC4626.sol";
import "../src/utils/IPool.sol";
import "../src/utils/IUniswapV2Router01.sol";
//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/


contract Account is AccountCore, ContractMetadata, ERC1271, ERC721Holder, ERC1155Holder {
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint public ghoThreshold;
    address public automationUpkeep;
    address public defaultToken;
    address public uniswapRouter;
    address public aavePool;
    address public vault;
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

    function initialize(address _defaultAdmin, bytes calldata _data) public override initializer {
        // This is passed as data in the _registerOnFactory() call in AccountExtension / Account.
        AccountCoreStorage.data().creationSalt = _generateSalt(_defaultAdmin, _data);
        _setAdmin(_defaultAdmin, true);
        automationUpkeep = msg.sender;
        allowedSupply = true;

        defaultToken = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60; //GHO
        uniswapRouter = 0x97f6E26dE5aD982eebC54819573156903a1d3024; 
        aavePool = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
        vault = 0xB9379DE0f8E2ed31b58828388eB3F619Cdf018d9;
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
        uint256 balance = IERC20(defaultToken).balanceOf(address(this));
        _registerOnFactory();
        _call(_target, _value, _calldata);
        uint256 endBalance = IERC20(defaultToken).balanceOf(address(this));
        if (endBalance < balance){
            ghoThreshold -= (balance - endBalance);
        }
    }

    /// @notice Executes a sequence transaction (called directly from an admin, or by entryPoint)
     function executeBatch(
        address[] calldata _target,
        uint256[] calldata _value,
        bytes[] calldata _calldata
    ) external virtual onlyAdminOrEntrypoint {
        uint256 balance = IERC20(defaultToken).balanceOf(address(this));
        _registerOnFactory();

        require(_target.length == _calldata.length && _target.length == _value.length, "Account: wrong array lengths.");
        for (uint256 i = 0; i < _target.length; i++) {
            _call(_target[i], _value[i], _calldata[i]);
        }
        uint256 endBalance = IERC20(defaultToken).balanceOf(address(this));
        if (endBalance < balance){
            ghoThreshold -= (balance - endBalance);
        } 
    }

    /// @notice Special function execution for ghost wallet. Execute a swap for defaultToken and supply on AAVE.
    function executeSwapAndSupply(
        address token
    ) external virtual onlyAdminOrUpkeep {
        require(allowedSupply, "Account: supply paused.");
        // Get token balance        
        uint balance = IERC20(token).balanceOf(address(this));
        // Accounts works with 6 decimals tokens (DAI, USDC)
        uint256 supplyAmount = balance % 1e6;
        uint256 swapAmount = balance - supplyAmount;
        // Get AAVE v3 bottor debt to repay
        (, uint debt, , , ,) = IPool(aavePool).getUserAccountData(address(this));
        
        if (supplyAmount > 0) {
            // We expect debt is lower than supplyAmount
            if (debt > 0 && supplyAmount <= debt){
                // Approve token to repay
                IERC20(token).approve(aavePool, supplyAmount);
                // Repay token to AAVE
                IPool(aavePool).repay(token, supplyAmount, 2, address(this));
            } else {
                // Supply token to AAVE
                IERC20(token).approve(aavePool, supplyAmount);
                // Supply token to AAVE
                IPool(aavePool).supply(token, supplyAmount, address(this), 0);
            }
        }
        // Swap token on Uniswap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = defaultToken; //GHO
        // Approve token to swap
        IERC20(token).approve(uniswapRouter, swapAmount);
        // Swap token on Uniswap
        uint256[] memory amountOut;
        (amountOut) = IUniswapV2Router01(uniswapRouter).swapExactTokensForTokens(swapAmount, swapAmount, path, address(this), block.timestamp);
        ghoThreshold += amountOut[1];
    }

    function executeSupplyToVault() public onlyAdminOrUpkeep() {
        // Get GHO balance
        uint ghoBalance = IERC20(defaultToken).balanceOf(address(this));
        uint ghoToSupply = ghoBalance % 1e18;
        // Approve GHO to vault
        IERC20(defaultToken).approve(vault, ghoToSupply);
        // Deposit GHO to vault
        IERC4626(vault).deposit(ghoToSupply, address(this));
        ghoThreshold = ghoBalance - ghoToSupply;
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