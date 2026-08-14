# Neverland Wrapped Tokens

<p>
  <a href="./README.md"><img src="https://img.shields.io/badge/Neverland%20Wrapped%20Tokens-v1.0.0%20%C2%B7%20Monad%20143%20%C2%B7%20Solidity%200.8.30%20%C2%B7%20Node%2022%20%C2%B7%20Foundry-192170?style=for-the-badge" alt="Neverland Wrapped Tokens v1.0.0 - Monad 143 - Solidity 0.8.30 - Node 22 - Foundry"/></a>
</p>

EIP-4626 static wrapper contracts for Neverland's rebasing Aave V3 nTokens on Monad Mainnet.

These wrappers convert rebasing nToken balances into fixed-balance ERC20 vault shares whose exchange rate grows over time. They are maintained by Neverland as the canonical wrapped-n-token implementation package for Monad deployments and downstream integrations. For the original upstream project documentation, see [README_ORIGINAL.md](./README_ORIGINAL.md).

## Package

Install the package:

```bash
npm install @neverland-money/wrapped-tokens
```

The package contains:

- `src/`: Solidity sources for the wrapper, factory, oracle, and interfaces.
- `scripts/`: Monad deployment, upgrade, verification, and fork-validation scripts.
- `tests/`: local unit and end-to-end reward/accounting tests.
- `audits/`: upstream static-a-token audit material.

Example wrapper interaction:

```solidity
// Deposit underlying, for example USDC, and receive wnUSDC.
IERC20(underlying).approve(address(wrapper), amount);
wrapper.deposit(amount, receiver, referralCode, true);

// Or deposit the nToken directly.
IERC20(nToken).approve(address(wrapper), amount);
wrapper.deposit(amount, receiver, referralCode, false);
```

## Neverland Changes

The Neverland setup keeps the upstream static-a-token vault architecture intact while adapting the reward and operations surface to the Neverland Monad deployment:

- Wrappers are deployed for Neverland nTokens and use `wn<SYMBOL>` symbols.
- Reward claims route through the Neverland `DustRewardsController`.
- Liquid DUST claims use the transfer-strategy direct-claim path, which splits the claimed amount 50/50 between the receiver and treasury.
- Locked DUST claims support creating a new veDUST lock, topping up an existing veDUST lock, or creating a permanent veDUST lock.
- `collectAndUpdateRewards(address)` is retained for ABI compatibility but is a no-op, so public callers cannot force wrapper-level liquid DUST claims.
- `getTotalClaimableRewards(address)` reports controller-pending wrapper rewards only; raw token balances already sitting on the wrapper are not shown as user-claimable rewards.
- `rescueERC20` and `rescueERC721` allow the current governance timelock to recover stranded non-accounting tokens and NFTs. The wrapper's backing nToken cannot be rescued because it backs outstanding shares.
- `REWARD_RESCUE_ADMIN()` resolves dynamically from the current EIP-1967 `ProxyAdmin.owner()`.

Neverland-specific reward tests live in [StaticATokenLM.DustRewards.t.sol](./tests/StaticATokenLM.DustRewards.t.sol) and [StaticATokenLM.E2E.t.sol](./tests/StaticATokenLM.E2E.t.sol).

## Runtime Boundary

Each wrapper is an ERC4626-style proxy whose accounting asset is the underlying reserve, while its backing balance is the corresponding Neverland nToken.

`totalAssets()` is the wrapper's nToken balance. Raw balances of underlying tokens, reward tokens, the wrapper's own shares, or unrelated ERC20s are not part of vault accounting. This is why rescue is blocked only for the backing nToken.

Reward economics are enforced by Neverland's controller and transfer strategy, not by the wrapper itself. In particular, the direct liquid DUST claim split is fixed 50/50; `DustLock.earlyWithdrawPenalty()` applies to early withdrawal from an existing lock, not to the wrapper's instant-claim split.

## Current Monad Mainnet Deployment

Chain ID: `143`

Initial deployment: February 2026

Latest implementation upgrade: June 6, 2026

Latest wrapper additions: August 14, 2026 (`wnCBBTC`, `wnXAUT0`)

### Core Infrastructure

| Contract                             | Address                                      | Notes                                      |
| ------------------------------------ | -------------------------------------------- | ------------------------------------------ |
| `StaticATokenFactory`                | `0x81148e8e1D9910080317E11c9f178559Ba23Bc80` | Factory proxy                              |
| `StaticATokenFactory` implementation | `0x6D48BeEa61aA165a54f0DD937919204F1A59ED1B` | Current implementation                     |
| `StaticATokenLM` implementation      | `0xD75D6Bf28519aCD719ae59Cbc47D9af0a0792af1` | Current wrapper implementation, revision 3 |
| `ProxyAdmin`                         | `0x0cBe49645BCC84eD90A6aA4D93dfEb2Cc836F721` | Admin for factory and wrapper proxies      |
| `ProxyAdmin.owner()`                 | `0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f` | Neverland governance timelock              |
| `TransparentProxyFactory`            | `0x8A93f9d1aEc306727cb70b3F500651C6a0Ccec0F` | Proxy factory                              |

### Referenced Protocol Contracts

| Contract                | Address                                      |
| ----------------------- | -------------------------------------------- |
| Aave V3 Pool            | `0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585` |
| Dust Rewards Controller | `0x57ea245cCbFAb074baBb9d01d1F0c60525E52cec` |

### Wrapped nTokens

| Asset    | Wrapped token                                | Symbol       | Name                       | Decimals |
| -------- | -------------------------------------------- | ------------ | -------------------------- | -------- |
| WMON     | `0xdB39A9D4a1f1b4e93A5684d602207628aD60613C` | `wnWMON`     | Wrapped Neverland WMON     | 18       |
| USDC     | `0x8d5c2Df3Eef09088Fcccf3376D8EcD0Dd505f642` | `wnUSDC`     | Wrapped Neverland USDC     | 6        |
| USDT0    | `0x4e8aaecCE10ad9394e96fE5f2bd4e587A7B04298` | `wnUSDT0`    | Wrapped Neverland USDT0    | 6        |
| WBTC     | `0x8959f4E6ED1f4567a464959793d5f8f6f33C1C8B` | `wnWBTC`     | Wrapped Neverland WBTC     | 8        |
| WETH     | `0xB3b850ac62B89fe9f4eFB652b516108a8aEb8848` | `wnWETH`     | Wrapped Neverland WETH     | 18       |
| sMON     | `0x08139339dd9A480CEB84D9C7CcE48BE436dB20b3` | `wnSMON`     | Wrapped Neverland sMON     | 18       |
| shMON    | `0x5e073494678fB7FA4a05bB17d45941Dd9Dc469c1` | `wnSHMON`    | Wrapped Neverland shMON    | 18       |
| gMON     | `0x29D2075E5151B1A6863bDC40EA86bD5e8aFd1705` | `wnGMON`     | Wrapped Neverland gMON     | 18       |
| AUSD     | `0x82c370ba90E38ef6Acd8b1b078d34fD86FC6bAC9` | `wnAUSD`     | Wrapped Neverland AUSD     | 6        |
| earnAUSD | `0xD45D54ad7Ae6D5dEdb0De7B283Fe0b4e2ba40217` | `wnEARNAUSD` | Wrapped Neverland earnAUSD | 6        |
| loAZND   | `0xD786F7569C39A9F64E6A54Eb77db21364E90F279` | `wnLOAZND`   | Wrapped Neverland loAZND   | 18       |
| cbBTC    | `0x98a297e6424787E57Af119949d7E00b721F832BB` | `wnCBBTC`    | Wrapped Neverland cbBTC    | 8        |
| XAUt0    | `0x22139A346b6312EB0A9812C67CfCe4A694676d59` | `wnXAUT0`    | Wrapped Neverland XAUt0    | 6        |

All 13 pool reserves are wrapped. The wrapper name comes from the underlying symbol and the wrapper symbol from the nToken symbol, both applied by the factory at creation.

### Wrapping a Newly Listed Reserve

Reserves are listed in `neverland-pool-operations`; wrapping them happens here, and the two are not otherwise linked. `NeverlandWrapperCoverageTest.test_everyPoolReserveHasAWrapper` walks the live reserve list and fails when a reserve has no wrapper, and `VerifyDeployment.s.sol` reports the same against live state.

To wrap one, add the reserve and its nToken to `NeverlandAddressBook.sol`, add it to `getNewReserves()` in the deploy script, then:

```bash
forge script scripts/VerifyPreDeployment.s.sol:VerifyPreDeployment --rpc-url monad -vv

forge script scripts/DeployAdditionalStaticTokens.s.sol:DeployAdditionalStaticTokens \
  --rpc-url monad --broadcast -vvv
```

`createStaticATokens` is permissionless, so the deployer needs no privileged role — only gas (roughly 1.3M per wrapper). The script skips reserves that already have a wrapper, so re-running it is safe, and it reverts if a created address does not match the pinned constant in `NeverlandAddressBook.sol`.

Wrapper addresses are CREATE2-deterministic — the factory salts on the underlying address — so a wrapper's address can be pinned in the address book before it is deployed. The salt does not cover `STATIC_A_TOKEN_IMPL`, so a pinned address is only valid while the factory keeps pointing at the same wrapper implementation. Deploy pending wrappers before an implementation upgrade, or re-derive the pins afterwards; `test_wrapperAddressPinsMatchChain` fails if a pin has gone stale.

## Reward Claims

```solidity
address[] memory rewards = new address[](1);
rewards[0] = DUST;

// Liquid claim. DUST is split 50/50 between receiver and treasury.
wrapper.claimRewards(receiver, rewards);

// Create or top up a lock. These paths avoid the instant liquid split.
wrapper.claimRewardsWithLock(receiver, rewards, lockTime, tokenId);

// Third-party claim, after DustRewardsController.setClaimer(user, claimer).
wrapper.claimRewardsOnBehalf(user, receiver, rewards);
```

Lock flag semantics:

- `tokenId > 0`: add DUST to an existing veDUST lock.
- `tokenId == 0 && lockTime > 0`: create a new veDUST lock.
- `tokenId == 0 && lockTime == type(uint256).max`: create a permanent veDUST lock.
- `tokenId == 0 && lockTime == 0`: liquid claim with the fixed 50/50 split.

## Rescue

```solidity
// Only REWARD_RESCUE_ADMIN(), currently the governance timelock.
wrapper.rescueERC20(token, receiver);
wrapper.rescueERC721(nft, receiver, tokenId);
```

Rescue can recover raw underlying, reward tokens, unrelated ERC20s, the wrapper's own shares, and stranded NFTs. It cannot rescue the backing nToken.

## Governance

The live ownership model is:

- `GovernanceTimelock` (`0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f`)
  - owns the static-wrapper `ProxyAdmin`
  - is the rescue admin resolved by `REWARD_RESCUE_ADMIN()`
  - is the delayed governance path for wrapper and factory upgrades
- Governance Safe (`0x57976e192C45461F5958045a0bC57102e90440eD`)
  - proposer, executor, and canceller on the governance timelock
  - does not directly own the static-wrapper `ProxyAdmin`

Shared governance transaction packages and multisig runbooks live in the `neverland-contracts` repository.

## Development

Use Node `22.18.0` via `.nvmrc`. Use Foundry for Solidity builds and tests. Use the local Prettier 2 Solidity plugin for formatting.

```bash
nvm use
cp .env.example .env
forge install
npm install

forge build --sizes
forge test -vv
npm run lint
```

Useful focused commands:

```bash
forge test --match-contract StaticATokenLMDustRewardsTest -vv
forge test --match-contract StaticATokenLME2ETest -vv
forge build --sizes --skip test
```

## Deployment Operations

Initial deployment scripts:

- `scripts/DeployMonad.s.sol`
- `scripts/VerifyPreDeployment.s.sol`
- `scripts/VerifyDeployment.s.sol`

Adding a wrapper for a newly listed reserve:

- `scripts/DeployAdditionalStaticTokens.s.sol`: creates wrappers for reserves that do not have one, without redeploying the factory infrastructure.

Implementation-upgrade scripts:

- `scripts/DeployUpgradeImplementations.s.sol`: deploys replacement implementations only.
- `scripts/ExportUpgradeSafeBatch.s.sol`: exports the ProxyAdmin upgrade batch input used by governance packaging.
- `scripts/ConfirmUpgradeFork.s.sol`: confirms the collect-hook fix and state preservation on a fork.
- `scripts/SimulateUpgradeFork.s.sol`: fork-applies the upgrade and proves deposit, withdraw, claim, and rescue behavior.
- `scripts/ValidateRewardsFork.s.sol`: exercises live reward paths on a fork.

The three upgrade scripts read the proxy set from `StaticATokenFactory.getStaticATokens()` at run time rather than from a hardcoded list. A hardcoded set would silently omit wrappers created after the script was last edited, leaving them on an implementation governance believed it had replaced. Any wrapper the factory has registered but the address book does not know about aborts the export.

Post-deploy verification example:

```bash
PROXY_ADMIN=0x0cBe49645BCC84eD90A6aA4D93dfEb2Cc836F721 \
TRANSPARENT_PROXY_FACTORY=0x8A93f9d1aEc306727cb70b3F500651C6a0Ccec0F \
STATIC_A_TOKEN_IMPL=0xD75D6Bf28519aCD719ae59Cbc47D9af0a0792af1 \
STATIC_A_TOKEN_FACTORY=0x81148e8e1D9910080317E11c9f178559Ba23Bc80 \
EXPECTED_PROXY_ADMIN_OWNER=0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f \
EXPECTED_REWARD_RESCUE_ADMIN=0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f \
forge script scripts/VerifyDeployment.s.sol:VerifyDeployment --rpc-url monad -vv
```

## Layout

- `src/StaticATokenLM.sol`: wrapper implementation.
- `src/StaticATokenFactory.sol`: factory implementation.
- `src/NeverlandAddressBook.sol`: Monad deployment constants used by scripts.
- `src/interfaces/`: public wrapper, factory, Dust controller, and helper interfaces.
- `scripts/`: deployment, upgrade, verification, and fork validation.
- `tests/`: local unit, E2E, reward, rescue, oracle, and meta-transaction tests.
- `tests/NeverlandWrapperCoverage.t.sol`: Monad-fork guard that every listed reserve has a wrapper, plus the address-book pins and wrapper metadata. Skips when `RPC_MONAD` is unset.

## Verification

Compilation settings:

- Solidity: `0.8.30`
- Optimizer: enabled
- Optimizer runs: `200000`

Current deployment verification targets:

- MonadScan: <https://monadscan.com>
- Sourcify / Blockvision: <https://sourcify-api-monad.blockvision.org>

## Upstream Provenance

This package is derived from BGD Labs' static aToken v3 codebase, which has since moved into Aave V3 Origin:

- Original README: [README_ORIGINAL.md](./README_ORIGINAL.md)
- Aave V3 Origin static-a-token: <https://github.com/aave-dao/aave-v3-origin/tree/main/src/contracts/extensions/stata-token>

Upstream licensing, attribution, and notices are preserved where they apply.

## Security

- Certora formal verification and manual review material from the upstream static-a-token project is available in [audits/](./audits/).
- Neverland-specific DUST reward, lock, rescue, and upgrade behavior is covered by local tests and fork-validation scripts in this repository.
- The upstream audit material does not by itself cover Neverland-specific reward distribution modifications.

## License And Notices

See [LICENSE](./LICENSE). Solidity sources retain their SPDX headers where applicable.

<p>
  <a href="https://neverland.money"><img src="https://img.shields.io/badge/Website-neverland.money-480052?style=for-the-badge&logo=safari&logoColor=white" height="22" alt="Website"/></a>
  <a href="https://app.neverland.money"><img src="https://img.shields.io/badge/App-app.neverland.money-192170?style=for-the-badge&logo=ethereum&logoColor=white" height="22" alt="App"/></a>
  <a href="https://x.com/Neverland_Money"><img src="https://img.shields.io/badge/X-%40Neverland__Money-1DA1F2?style=for-the-badge" height="22" alt="X"/></a>
  <a href="https://discord.com/invite/neverland"><img src="https://img.shields.io/badge/Discord-Join%20Server-5865F2?style=for-the-badge&logo=discord&logoColor=white" height="22" alt="Discord"/></a>
</p>
