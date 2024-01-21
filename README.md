# GHOst Wallet

<div style="flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center">
  <img src="https://github.com/builders-garden/ghost-app/blob/main/assets/icon.png" width="200" height="200" />
  <p>
    <b>GHOst</b> is a native wallet for managing your GHO tokens.
  </p>
</div>

## 👻 LFGHO Hackathon

This project was built during the [ETHGlobal LFGHO Hackathon](https://ethglobal.com/events/lfgho).

### 💰 Tracks

We are applying for the following tracks:

- **AAVE Payments**: we developed a native wallet that leverages AA (ERC-4337) to simplify the experience of sending, receiving and borrowing GHO tokens;
- **AAVE Vaults**: we developed an ERC-4626 GHO Vault that allows users to deposit GHO tokens and use them as liquidity provider into a GHO/USDC Uniswap pool. This vault is also auto-populated when users receive GHO tokens and all the GHOst users share the same vault contract. Also, any remainder of USDT or USDC tokens received by the user is automatically sent to AAVE Lending Contracts;
- **AAVE Integration Prize**: for allowing users to manage GHO tokens seamlessly by using their email address or Google account.
- **Chainlink CCIP** users can send GHO token across different EVM chains. Gho is locked and burned 

## :link: GHOst contract addresses:

- **Account Factory**: [0x543F0BB75a4B76B7fF8253A283D1137A7E354fe3](https://sepolia.etherscan.io/address/0x543F0BB75a4B76B7fF8253A283D1137A7E354fe3)
- **Ghost Vault**:   [0x6801402aE64a287d172f5c79b5b1e14505019494](https://sepolia.etherscan.io/address/0x6801402aE64a287d172f5c79b5b1e14505019494)
- **Mocked Router**: [0xC847fe71906748A56cA211D0189d8b7798A60cDD](https://sepolia.etherscan.io/address/0xC847fe71906748A56cA211D0189d8b7798A60cDD)
- **Ghost Portal Sepolia**:  [0x3d7eB0E00D7E0a0943C926E5D3bd92E414fc44dd](https://sepolia.etherscan.io/address/0x3d7eB0E00D7E0a0943C926E5D3bd92E414fc44dd)
- **Ghost Portal Mumbai**:   [0x3674a4fbedd210fe6c82def29b8b3f9fd6324c49](https://sepolia.etherscan.io/address/0x3674a4fbedd210fe6c82def29b8b3f9fd6324c49)

## ⚒️ GHOst Features

GHOst is the first GHO native wallet; this means that everything is built around GHO tokens: transfers, deposits, withdrawals, borrows. It allows users to create a new Smart Wallet by using their email address or Google account. Once the account is created, a custom Smart Account contract is created in order to automatically swap between received USDT or USDC tokens into GHO.

All the transactions are made leveraging the ERC-4337 Account Abstraction standard using the Thirdweb paymaster: **no fees or signing allowed in GHOst**.

Every time a user receives USDT, USDC or GHO, the remainder rounded to nearest dollar (eg. you receive $1.30, $0.30 will be set aside) is sent to:

- **AAVE Lending Contracts** in the case of **USDT** or **USDC**. The rest (eg. $1) is automatically swapped to GHO (on Sepolia using a Mock Uniswap Router) and sent to the user's Smart Account. Here these tokens maybe used by the user in the future to borrow some GHO, or they can leave them there to accrue some interest;
- **GHO Vault** in the case of GHO. The rest (eg. $1) is sent to the user's Smart Account. The tokens inside the GHO Vault are then used as liquidity provider into a GHO/USDC Uniswap pool.

In addition to this, when a GHOst user wants to send GHO tokens to another user and the sender doesn't have enough GHO tokens in their Smart Account, the app **will automatically borrow** the required amount from the AAVE Lending Contracts to match the amount and send it to the recipient.

## 📱 App features

GHOst wallet allows users to:

- [x] Create a Smart Wallet using their email address or Google account that can be exported to any Ethereum wallet via the private key;
- [x] Seamlessly transfer GHO tokens to other users using their GHOst username;
- [x] View their total **Pocket** balance (GHO Vault Balance + AAVE Lending Balance);
- [x] Deposit or withdraw GHO tokens from the GHO Vault;
- [x] Borrow or repay GHO tokens from the AAVE Protocol.

## 💻 Tech Stack

GHOst contracts is built using Openzeppelin, Chainlink Automation, Chainlink CCIP and Thirdweb Abstracted Account factory.

### 📦 Run locally

You need to [install foundry](https://book.getfoundry.sh/getting-started/installation)

Once the dependencies are installed, navigate to foundry folder:

```bash
# Compile contracts
forge build 
```

