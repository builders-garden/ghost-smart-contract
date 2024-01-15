// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MockRouter {

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length == 2, "MockRouter: path length must be 2");
        // Mock Router only supports 6 decimals stablecoin to GHO
        uint256 amountOut = amountIn*1e12;
        IERC20(path[1]).transfer(msg.sender, amountOut); 
        return amounts;
    }
}