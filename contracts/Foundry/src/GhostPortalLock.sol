// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/utils/BasicMessageReceiver.sol";
import "../src/utils/BasicMessageSender.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract GhostPortalLock is BasicMessageReceiver, BasicMessageSender  {
    
    
    address ghoToken = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60; 
    address mumbai_portal;
    uint64 destinationChainSelector = 12532609583862916517;

    constructor(address router, address link)BasicMessageReceiver(router) BasicMessageSender(router, link){

    }

    function getLockedGho() external view returns (uint256) {
        return IERC20(ghoToken).balanceOf(address(this));
    }

    function setPortal(address portal) public {
        require(mumbai_portal == address(0));
        mumbai_portal = portal;
    }

    function send(
        address to, 
        uint256 amount
        ) external returns (bytes32 messageId){
        string memory messageText =  string(abi.encode(to, amount));
        messageId = send(destinationChainSelector, mumbai_portal, messageText, BasicMessageSender.PayFeesIn.LINK);
        IERC20(ghoToken).transferFrom(msg.sender, address(this), amount);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override(BasicMessageReceiver){
        latestMessageId = message.messageId;
        latestSourceChainSelector = message.sourceChainSelector;
        latestSender = abi.decode(message.sender, (address));
        latestMessage = abi.decode(message.data, (string));
        // require sender == portal 
        bytes memory decodedBytes = bytes(latestMessage);
        (address to, uint amount) = abi.decode(decodedBytes, ((address), (uint)));

        IERC20(ghoToken).transfer(to, amount);
        
        emit MessageReceived(
            latestMessageId,
            latestSourceChainSelector,
            latestSender,
            latestMessage
        );
    }

}




