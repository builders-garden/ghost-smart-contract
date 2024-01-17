// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/utils/ERC4626.sol";

contract MyERC4626Vault is ERC4626 {

    constructor(address _token, string memory name, string memory symbol) ERC4626(IERC20Metadata(_token)) ERC20(name, symbol) {}

    //TODO: Add LP logic (add, withdraw, etc.)
}