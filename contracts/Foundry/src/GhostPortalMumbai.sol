// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./BasicMessageReceiver.sol";
import "./BasicMessageSender.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract GhostPortal is BasicMessageReceiver, BasicMessageSender, ERC20  {
    
    address sepolia_portal;
    uint64 destinationChainSelector = 16015286601757825753;

    constructor(address router, address link)
        BasicMessageReceiver(router)
        BasicMessageSender(router, link)
        ERC20("bGho", "bGho")  {}

    function setPortal(address portal) public {
        require(sepolia_portal == address(0));
        sepolia_portal = portal;
    }

    function burnTokenAndSend(
        address to, 
        uint256 amount
        ) external returns (bytes32 messageId){
        
        string memory messageText =  string(abi.encode(to, amount));
        messageId = send(destinationChainSelector, sepolia_portal, messageText, BasicMessageSender.PayFeesIn.LINK);
        _burn(to, amount);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override(BasicMessageReceiver){
        latestMessageId = message.messageId;
        latestSourceChainSelector = message.sourceChainSelector;
        latestSender = abi.decode(message.sender, (address));
        latestMessage = abi.decode(message.data, (string));
        require(latestSender == sepolia_portal, "Invalid message sender from origin chain");
        bytes memory decodedBytes = bytes(latestMessage);
        (address to, uint amount) = abi.decode(decodedBytes, ((address), (uint)));
        _mint(to, amount);
        
        emit MessageReceived(
            latestMessageId,
            latestSourceChainSelector,
            latestSender,
            latestMessage
        );
    }


}




