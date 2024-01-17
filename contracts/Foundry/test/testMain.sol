// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "std/test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/AccountFactory.sol";
import "../src/Account.sol";

contract Test_Sample is Test {
   
    AccountFactory internal upkeep;
    ERC20 internal usdc;
    address accFactory = 0x5155E7068EdfF80B5075b0EF763dbA2Fe1f25774;
    address acc = 0x7c2a16aD81F4CF29de9664029929F8Af4dC8F07D;
    function setUp() public {
        
    }

    
    function testIntegration() public {
        vm.prank(accFactory);
        Account(payable(acc)).executeSwapAndSupply(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8);
    }


    
}   
