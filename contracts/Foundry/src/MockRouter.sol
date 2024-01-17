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
    ) external returns (uint amountOut) {
        require(path.length != 0, "MockRouter: path length");
        // Mock Router only supports 6 decimals stablecoin to GHO
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = amountIn*1e12;
        IERC20(path[1]).transfer(msg.sender, amountOut); 
        return amountOut;
    }
}