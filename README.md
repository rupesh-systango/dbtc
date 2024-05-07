# DBC


## Getting started
DBC is a platform designed for users to predict the future prices of cryptocurrencies. Users who make accurate predictions are rewarded with extra tokens. This document outlines the functionalities and processes of the DBC smart contract.


## Contract Overview

This smart contract, named DBTI, is designed to facilitate trade-related functionalities securely on the Ethereum blockchain. It is implemented in Solidity version 0.8.20 and incorporates various features and roles to ensure proper access control, pausability, and protection against reentrancy attacks.

## Features

- <b>`ERC721 Compatibility:`</b> The contract inherits from ERC721Upgradeable, making it compatible with the ERC721 standard for non-fungible tokens (NFTs).

- <b>`Access Control:`</b> Utilizes AccessControlUpgradeable to define roles such as admin and signer, allowing for granular access control over contract functions.

- <b>`Pausable:`</b> Implements PausableUpgradeable to enable the contract owner to pause and unpause certain functions, enhancing security and mitigating potential risks during unforeseen circumstances.

- <b>`Reentrancy Guard:`</b> Incorporates ReentrancyGuardUpgradeable to prevent reentrancy attacks, ensuring that functions cannot be called recursively to manipulate contract state.

- <b>`ECDSA Signature Verification:`</b> Utilizes ECDSA signatures for trade authorization, ensuring that trades are initiated and resolved securely.


## Key Functions

`initialize()`
- `Description:` Initializes the contract with essential parameters and sets up initial roles.
- `Parameters:`
  - _thresholdAmount: The threshold amount to be considered valid.
  - _treasuryAccount: The address where trade fees are transferred.
  - name: The name of the ERC-721 token.
  - symbol: The symbol of the ERC-721 token.
  - admin: The address designated as the initial admin role.
  - signer: The address designated as the initial signer role.

`createTrade()`
- `Description:` Places a new trade with encoded data and signature.
- `Parameters:`
  - encodedTradeData: The encoded data with the trade details.
  - signature: The signature of the user request with trade data.
  - tokenMetadata: Metadata associated with the ERC-721 token.

`resolveTrade()`
- `Description:` Resolves a trade.
- `Parameters:`
  - tradeId: The ID of the trade to resolve.

`claimTrade()`
- `Description:` Allows the owner of specified trades to claim their rewards.
- `Parameters:`
  - encodedTradeData: The encoded data containing trade IDs and expiry timestamp.
  - signature: The signature of the user request with trade data.

`updateThresholdAmount()`
- `Description:` Updates the threshold amount.
- `Parameters:`
  - amount: The new threshold amount.

## Access Control
<b>Admin Role:</b> Has access to critical functions such as pausing/unpausing the contract, adding/removing admins and signers, and updating the threshold amount.

<b>Signer Role:</b> Has the authority to sign trade requests, validating their authenticity.

## External Dependencies
The contract relies on external libraries and contracts for various functionalities:

OpenZeppelin contracts for ERC721, access control, pausability, and reentrancy guard.
ECDSALib for ECDSA signature verification.

## Lines of Code:

  Language                 |   Files  |    Blank |  Comment |     Code |                
---------------------------|----------|----------|----------|----------|
Solidity                   |    1     |       44 |      105 |   339 |                |
---------------------------|----------|----------|----------|----------|