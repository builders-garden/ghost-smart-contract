// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LinkTokenInterface} from "@chainlink/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/src/v0.8/ccip/libraries/Client.sol";


/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract BasicMessageSender {
    enum PayFeesIn {
        Native,
        LINK
    }

    address immutable i_routerSender;
    address immutable i_link;

    event MessageSent(bytes32 messageId);

    constructor(address router, address link) {
        i_routerSender = router;
        i_link = link;
    }

    receive() external payable {}

    function send(
        uint64 destinationChainSelector,
        address receiver,
        string memory messageText,
        PayFeesIn payFeesIn
    ) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(messageText),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: payFeesIn == PayFeesIn.LINK ? i_link : address(0)
        });

        uint256 fee = IRouterClient(i_routerSender).getFee(
            destinationChainSelector,
            message
        );

        if (payFeesIn == PayFeesIn.LINK) {
            LinkTokenInterface(i_link).approve(i_routerSender, fee);
            messageId = IRouterClient(i_routerSender).ccipSend(
                destinationChainSelector,
                message
            );
        } else {
            messageId = IRouterClient(i_routerSender).ccipSend{value: fee}(
                destinationChainSelector,
                message
            );
        }

        emit MessageSent(messageId);
    }
}
