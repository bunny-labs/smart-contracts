# `Distributor.sol` - ERC20 token distribution contract

## Overview

`Distributor` is a contract for distributing a specific ERC20 token (`asset`) to a fixed number of members.
Each membership in the distribution is represented by an ERC721 NFT and has a number of shares associated to it.
Members receive tokens proportionally to the number of shares their membership has.

## Depositing

There are two main ways of depositing tokens into a `Distributor` contract.

### Member-initiated deposits

**Scenario:** Tokens are periodically sent to a `treasury` address.

1. `treasury` gives approval for `Distributor` to move its tokens. This can be a limited approval if the total amount of `asset` that will be eventually distributed is known in advance.
2. A member calls the `deposit()` method in `Distributor` which transfers the entire balance of the `asset` token from `treasury` to `Distributor`, registers the deposit and makes it available for claiming.

### Direct transfers

Alternatively, an approval-less workflow is possible.

1. `asset` tokens are transferred to the `Distributor` contract from any address.
2. A member of the `Distributor` needs to call the `register()` method. This checks how many new tokens have been added to the contract and makes them available for members to claim.

## Claiming

To claim any undistributed `asset` tokens, use the `claim(uint256 membershipId)` method.
Members who hold multiple membership tokens can claim them as a batch using `claim(uint256[] membershipIds)`.

## Metadata

The contract generates the following NFT attributes on-chain:

- Membership #
- no. of shares
- no. of claimable tokens

The image URI for the membership NFTs is set when deploying the contract and cannot be changed later.
