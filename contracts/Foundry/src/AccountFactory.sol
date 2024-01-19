// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Utils
import "@thirdweb/prebuilts/account/utils/BaseAccountFactory.sol";
import "@thirdweb/prebuilts/account/utils/BaseAccount.sol";
import "@thirdweb/external-deps/openzeppelin/proxy/Clones.sol";

// Extensions
import "@thirdweb/extension/upgradeable/PermissionsEnumerable.sol";
import "@thirdweb/extension/upgradeable/ContractMetadata.sol";

// Interface
import "@thirdweb/prebuilts/account/interface/IEntrypoint.sol";

// Smart wallet implementation
import { Account } from "./Account.sol";

// Chainlink automation interface
//import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@chainlink/src/v0.8/automation/AutomationCompatible.sol";


// Openzeppelin IERC20.sol
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AccountFactory is
  BaseAccountFactory,
  ContractMetadata,
  PermissionsEnumerable,
  AutomationCompatible
{
  address internal owner;
  address internal upkeep;
  address internal uniswapRouter;
  address internal ghoAddress = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60;
  address[] internal s_swappableERC20 = [
    0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8, //usdc
    0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0 //usdt
  ];

  /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/
  constructor(
    address _defaultAdmin,
    IEntryPoint _entrypoint
  )
    BaseAccountFactory(
      address(new Account(_entrypoint, address(this))),
      address(_entrypoint)
    )
  {
    _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
  }

  /// @dev Initializes the Factory upkeep using Chainlink Automation.
  function initializeUpkeepAndRouter(address _upkeep) public {
    require(upkeep == address(0), "Already initialized");
    upkeep = _upkeep;
  }

  /*///////////////////////////////////////////////////////////////
                            Modifiers 
    //////////////////////////////////////////////////////////////*/
  modifier onlyUpkeep() {
    require(msg.sender == upkeep, "Only upkeep allowed");
    _;
  }
  modifier onlyOwner() {
    require(msg.sender == owner, "Only owner allowed");
    _;
  }

  /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

  /// @dev Called in `createAccount`. Initializes the account contract created in `createAccount`.
  function _initializeAccount(
    address _account,
    address _admin,
    bytes calldata _data
  ) internal override {
    Account(payable(_account)).initialize(_admin, _data);
  }

  /// @dev Returns whether contract metadata can be set in the given execution context.
  function _canSetContractURI() internal view virtual override returns (bool) {
    return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /// @notice Returns the sender in the given execution context.
  function _msgSender()
    internal
    view
    override(Multicall, Permissions)
    returns (address)
  {
    return msg.sender;
  }

  /*///////////////////////////////////////////////////////////////
                        Chainlink functions
    //////////////////////////////////////////////////////////////*/

  /**
   * @dev checkUpkeep function called off-chain by Chainlink Automation infrastructure
   * @dev Checks for balances elegible for swap
   * @return upkeepNeeded A boolean indicating whether upkeep is needed.
   * @return performData The performData parameter triggering the performUpkeep
   * @notice This function is external, view, and implements the Upkeep interface.
   */
  function checkUpkeep(
    bytes calldata
  )
    external
    view
    override
    returns (bool upkeepNeeded, bytes memory performData)
  {
    (upkeepNeeded, performData) = _checkUpkeep();
  }

  function _checkUpkeep() internal view returns (bool, bytes memory) {
    address[] memory swappableERC20 = s_swappableERC20;
    address[] memory wallets = getAllAccounts();
    address[] memory tokensToSwap = new address[](swappableERC20.length);
    address[] memory filteredTokensToSwap;
    uint count;
    for (uint i; i < wallets.length; ++i) {
      for (uint j; j < swappableERC20.length; ++j) {
        if (IERC20(swappableERC20[j]).balanceOf(wallets[i]) > 0) {
          tokensToSwap[count] = swappableERC20[j];
          ++count;
        }
      }
      uint ghoTreshold = Account(payable(wallets[i])).ghoThreshold();
      uint ghoBalance = IERC20(ghoAddress).balanceOf(wallets[i]);

      bool ghoReceived = (
        (ghoBalance > ghoTreshold) && (ghoBalance % 1e18 > 0) ? true : false
      );
      filteredTokensToSwap = new address[](count);
      for (uint k; k < count; ++k) {
        filteredTokensToSwap[k] = tokensToSwap[k];
      }

      if (filteredTokensToSwap.length > 0 || ghoReceived) {
        return (
          true,
          abi.encode(wallets[i], filteredTokensToSwap, ghoReceived)
        );
      }
    }
  }

  /**
   * @dev performUpkeep function called by Chainlink Automation infrastructure after checkUpkeep checks
   * @param performData the data inputed by Chainlink Automation retrieved by checkUpkeep
   */
  function performUpkeep(
    bytes calldata performData
  ) external override(AutomationCompatibleInterface) onlyUpkeep {
    (address wallet, address[] memory tokensToSwap, bool ghoReceived) = abi
      .decode(performData, (address, address[], bool));
    for (uint i; i < tokensToSwap.length; ++i) {
      Account(payable(wallet)).executeSwapAndSupply(tokensToSwap[i]);
    }
    if (ghoReceived) {
      Account(payable(wallet)).executeSupplyToVault();
    }
  }
}
