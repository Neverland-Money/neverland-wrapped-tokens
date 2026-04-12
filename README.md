# Static NToken Wrapper - Neverland Deployment

> **Note:** This README is specific to the Neverland deployment on Monad Mainnet. For the original project documentation, see [README_ORIGINAL.md](./README_ORIGINAL.md).

## Overview

This repository contains the Neverland deployment of EIP-4626 compliant wrapper tokens for Neverland's Aave V3 NTokens on Monad Mainnet. These static wrappers convert rebasing NTokens into standard ERC20 tokens with a fixed balance and growing exchange rate, making them compatible with DeFi protocols that don't support rebasing tokens.

## Deployed Contracts (Monad Mainnet)

**Chain ID:** 143  
**Network:** Monad Mainnet  
**Deployment Date:** February 2026

### Core Infrastructure

| Contract                                 | Address                                      | Description                                      |
| ---------------------------------------- | -------------------------------------------- | ------------------------------------------------ |
| **StaticATokenFactory**                  | `0x81148e8e1D9910080317E11c9f178559Ba23Bc80` | Main factory for creating wrapped tokens (Proxy) |
| **StaticATokenFactory (Implementation)** | `0x73006F5e72Af8d593BB7c029EAaFBc4D4b535A7B` | Factory implementation contract                  |
| **StaticATokenLM (Implementation)**      | `0xF20a545013B74F7Ed0239399217B130e4177E085` | Template for wrapped static NTokens              |
| **ProxyAdmin**                           | `0x0cBe49645BCC84eD90A6aA4D93dfEb2Cc836F721` | Manages proxy upgrades                           |
| **ProxyAdmin Owner**                     | `0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f` | GovernanceTimelock (24h delayed governance)      |
| **TransparentProxyFactory**              | `0x8A93f9d1aEc306727cb70b3F500651C6a0Ccec0F` | Creates transparent proxies                      |

### Referenced Aave Contracts

| Contract               | Address                                      |
| ---------------------- | -------------------------------------------- |
| **Aave V3 Pool**       | `0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585` |
| **Rewards Controller** | `0x57ea245cCbFAb074baBb9d01d1F0c60525E52cec` |

### Wrapped Static NTokens

All wrapped tokens follow the naming convention `wn<SYMBOL>` (e.g., "wnWMON" for wrapped nWMON).

| Asset        | Wrapped Token Address                        | Symbol     | Name                       | Decimals |
| ------------ | -------------------------------------------- | ---------- | -------------------------- | -------- |
| **WMON**     | `0xdB39A9D4a1f1b4e93A5684d602207628aD60613C` | wnWMON     | Wrapped Neverland WMON     | 18       |
| **USDC**     | `0x8d5c2Df3Eef09088Fcccf3376D8EcD0Dd505f642` | wnUSDC     | Wrapped Neverland USDC     | 6        |
| **USDT0**    | `0x4e8aaecCE10ad9394e96fE5f2bd4e587A7B04298` | wnUSDT0    | Wrapped Neverland USDT0    | 6        |
| **WBTC**     | `0x8959f4E6ED1f4567a464959793d5f8f6f33C1C8B` | wnWBTC     | Wrapped Neverland WBTC     | 8        |
| **WETH**     | `0xB3b850ac62B89fe9f4eFB652b516108a8aEb8848` | wnWETH     | Wrapped Neverland WETH     | 18       |
| **sMON**     | `0x08139339dd9A480CEB84D9C7CcE48BE436dB20b3` | wnSMON     | Wrapped Neverland sMON     | 18       |
| **shMON**    | `0x5e073494678fB7FA4a05bB17d45941Dd9Dc469c1` | wnSHMON    | Wrapped Neverland shMON    | 18       |
| **gMON**     | `0x29D2075E5151B1A6863bDC40EA86bD5e8aFd1705` | wnGMON     | Wrapped Neverland gMON     | 18       |
| **AUSD**     | `0x82c370ba90E38ef6Acd8b1b078d34fD86FC6bAC9` | wnAUSD     | Wrapped Neverland AUSD     | 6        |
| **earnAUSD** | `0xD45D54ad7Ae6D5dEdb0De7B283Fe0b4e2ba40217` | wnEARNAUSD | Wrapped Neverland earnAUSD | 6        |
| **loAZND**   | `0xD786F7569C39A9F64E6A54Eb77db21364E90F279` | wnLOAZND   | Wrapped Neverland loAZND   | 18       |

## Contract Verification

All contracts are verified on:

- **MonadScan** (Etherscan): https://monadscan.com
- **Sourcify (Blockvision)**: https://sourcify-api-monad.blockvision.org

**Compilation Settings:**

- Solidity Version: `v0.8.30+commit.737f2a01`
- EVM Version: `prague`
- Optimizer: Enabled
- Optimizer Runs: `200000`

## How It Works

### Static Wrappers

The wrapped tokens (wn\*) are EIP-4626 compliant vaults that:

1. **Wrap rebasing NTokens** into standard ERC20 tokens with fixed balances
2. **Accrue yield** through an increasing exchange rate instead of balance changes
3. **Track liquidity mining rewards** from the Aave rewards controller
4. **Support meta-transactions** via EIP-2612 permits

### Key Features

- **Full EIP-4626 Compatibility**: Standard vault interface for deposits, withdrawals, and accounting
- **Reward Tracking**: Automatically tracks and allows claiming of DUST rewards
- **Non-Rebasing**: Balance stays constant while the exchange rate increases
- **Composability**: Compatible with DeFi protocols that don't support rebasing tokens
- **Upgradeable**: Managed through GovernanceTimelock (24h delayed governance lane)

### Reward Distribution

The wrapped tokens integrate with Neverland's reward distribution system:

- Rewards accrue to wrapper holders based on their share of deposits
- Supports liquid claims (with early withdrawal penalty enforced by the [DustLockTransferStrategy](https://github.com/Neverland-Money/neverland-contracts/blob/main/src/emissions/DustLockTransferStrategy.sol)) and locked claims (via veNFT) using the [DustRewardsController](https://github.com/Neverland-Money/neverland-contracts/blob/main/src/emissions/DustRewardsController.sol)
- Rewards can be claimed on behalf of users by authorized claimers
- Multiple reward tokens can be supported per wrapper

## Usage

### Depositing

```solidity
// Deposit underlying asset (e.g., USDC) and receive wrapped tokens
IERC20(underlying).approve(address(wrapper), amount);
wrapper.deposit(amount, receiver, referralCode, true);

// Or deposit NTokens directly
IERC20(nToken).approve(address(wrapper), amount);
wrapper.deposit(amount, receiver, referralCode, false);
```

### Withdrawing

```solidity
// Redeem wrapped tokens for underlying asset
wrapper.redeem(shares, receiver, owner);

// Or withdraw specific amount
wrapper.withdraw(assets, receiver, owner);
```

### Claiming Rewards

```solidity
// Claim rewards with liquid option (subject to penalty)
address[] memory rewards = new address[](1);
rewards[0] = DUST_ADDRESS;
wrapper.claimRewards(receiver, rewards);

// Claim rewards with lock (no penalty, creates or adds to veNFT)
// See "Lock Flags" in Notes below for lockTime/tokenId semantics.
wrapper.claimRewardsWithLock(receiver, rewards, lockDuration, tokenId);

// Claim on behalf (requires setClaimer on RewardsController)
wrapper.claimRewardsOnBehalf(onBehalfOf, receiver, rewards);
```

## Governance

The live ownership model after the April 10, 2026 governance cutover is:

- `GovernanceTimelock` (`0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f`)
  - current owner of `StaticAToken ProxyAdmin`
  - delayed governance path for wrapper upgrades and other actions gated by `StaticAToken ProxyAdmin.owner()`
- Governance Safe (`0x57976e192C45461F5958045a0bC57102e90440eD`)
  - proposer / executor / canceller on `GovernanceTimelock`
  - no longer directly owns `StaticAToken ProxyAdmin`

Operationally, this means upgrades to `StaticATokenFactory` and the wrapper proxies administered by `StaticAToken ProxyAdmin` must now flow through the shared Neverland governance timelock instead of direct Safe execution.

This repository is the canonical implementation repo for the static wrapper system. The shared governance rules, timelock tasks, and migration runbooks live in [`neverland-contracts`](https://github.com/Neverland-Money/neverland-contracts).

## Development

This project uses [Foundry](https://getfoundry.sh).

### Setup

```sh
cp .env.example .env
forge install
```

### Test

```sh
forge test
```

### Format

```sh
forge fmt
```

### Deploy

Deployment scripts are located in `scripts/`:

- `DeployMonad.s.sol`: Main deployment script for Monad
- `VerifyDeployment.s.sol`: Post-deployment verification

## Security

### Audits

- Certora formal verification (see [audits/](./audits/))
- Extensive test suite covering all critical functionality

**Disclaimer:** The audits linked above do not cover the Neverland‑specific reward distribution modifications in this repository.

### Verification Status

✓ All contracts verified on MonadScan (Etherscan) and MonadVision (Blockvision - Sourcify)

## Architecture

```
StaticATokenFactory (Proxy)
└── Creates individual wrapped tokens via TransparentProxyFactory
    └── Each wrapper is a StaticATokenLM proxy
        ├── Deposits underlying → receives NTokens → tracks as shares
        ├── Accrues yield through exchange rate
        └── Tracks rewards from DustRewardsController
```

## Important Notes

1. **Reward Registration**: `refreshRewardTokens()` is called during `initialize()` if the incentives controller is set. Manual refresh is only needed if new rewards are added later.
2. **Exchange Rate**: Always increasing (barring Aave v3 shortfall events)
3. **Gas Considerations**: Monad charges the full gas limit, not just used gas
4. **Penalty**: Liquid reward claims incur an early withdrawal penalty that goes to the treasury

## Notes

- **Wrapper vs. Controller**: Economic logic (penalty + locking) is enforced by the [DustLockTransferStrategy](https://github.com/Neverland-Money/neverland-contracts/blob/main/src/emissions/DustLockTransferStrategy.sol), not by the wrapper. See [audits](https://github.com/Neverland-Money/neverland-contracts/tree/main/audits).
- **Claim Paths**: Wrapper claims default to liquid (lockTime=0, tokenId=0). Locked claims are supported but require explicit caller inputs.
- **Lock Flags** (see [DustLockTransferStrategy](https://github.com/Neverland-Money/neverland-contracts/blob/main/src/emissions/DustLockTransferStrategy.sol)):
  - `tokenId > 0` → add DUST to existing veDUST
  - `tokenId == 0 && lockTime > 0` → create new veDUST lock
  - `tokenId == 0 && lockTime == type(uint256).max` → create permanent veDUST lock
  - `tokenId == 0 && lockTime == 0` → liquid claim with earlyWithdrawPenalty
- **On‑Behalf Claims**: Requires `setClaimer(user, claimer)` on the rewards controller before a third‑party distributor can claim.
- **Post‑Deploy Validation**: Run `scripts/VerifyDeployment.s.sol` on mainnet and optionally `scripts/SmokeTestMainnet.s.sol` with small amounts.

## License

See [LICENSE](./LICENSE) file for details.
