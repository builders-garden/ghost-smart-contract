// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouter {
    address public gho = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory) {

        bool decimalCheck; // This should be based on some logic
        uint256 amountOut;
        if (path[0] == gho){
            decimalCheck = true;
        }
        if (decimalCheck) {
            amountOut = amountIn / (10**(18-6));
        } else {
            amountOut = amountIn * (10**(18-6));
        }
        // Mock token transfer logic (Uncomment in actual logic)
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(msg.sender, amountOut); 

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }
}