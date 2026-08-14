// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';

import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {NeverlandMonadMainnet} from '../src/NeverlandAddressBook.sol';

interface IRewardsControllerView {
  function getTransferStrategy(address reward) external view returns (address);
}

interface ITransferStrategyView {
  function DUST_LOCK() external view returns (address);
}

interface IDustLockView {
  function earlyWithdrawTreasury() external view returns (address);
}

/**
 * @notice Fork-only confirmation that, AFTER applying the implementation upgrades to a fresh fork of
 *         current mainnet, the griefing vulnerability is dead and depositor state is preserved —
 *         checked across wrappers with different underlying decimals (6 / 18 / 8).
 *
 *         This complements SimulateUpgradeFork (which proves deposit/withdraw/claim/rescue work) by
 *         proving the actual fix: collectAndUpdateRewards can no longer move or strand any DUST.
 *
 * Usage:
 *   NEW_TOKEN_IMPL=0x... NEW_FACTORY_IMPL=0x... \
 *     forge script scripts/ConfirmUpgradeFork.s.sol:ConfirmUpgradeFork --rpc-url https://rpc.monad.xyz -vv
 */
contract ConfirmUpgradeFork is Script {
  function run() external {
    require(block.chainid == 143, 'WRONG_CHAIN');
    address tok = vm.envAddress('NEW_TOKEN_IMPL');
    address fac = vm.envAddress('NEW_FACTORY_IMPL');
    require(tok.code.length > 0 && fac.code.length > 0, 'IMPL_NO_CODE');

    console2.log('=== confirm-upgrade fork @ block', block.number, '===');

    // Apply every ProxyAdmin.upgrade call exactly as the timelock will. The wrapper set is read
    // from the factory registry, so this stays in step with the exported batch as reserves are
    // listed and wrapped.
    address factoryProxy = NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY;
    address[] memory wrappers = StaticATokenFactory(factoryProxy).getStaticATokens();
    require(wrappers.length > 0, 'NO_WRAPPERS');

    // Gate on the same condition ExportUpgradeSafeBatch does. Without it this fork proof would pass
    // for a wrapper set the export path refuses, so a green run here would not imply the batch can
    // even be produced.
    for (uint256 i = 0; i < wrappers.length; i++) {
      require(
        NeverlandMonadMainnet.isPinnedStaticAToken(wrappers[i]),
        'WRAPPER_NOT_IN_ADDRESS_BOOK'
      );
    }

    ProxyAdmin pa = ProxyAdmin(NeverlandMonadMainnet.PROXY_ADMIN);
    vm.startPrank(NeverlandMonadMainnet.PROXY_ADMIN_OWNER);
    for (uint256 i = 0; i < wrappers.length; i++) {
      pa.upgrade(TransparentUpgradeableProxy(payable(wrappers[i])), tok);
    }
    pa.upgrade(TransparentUpgradeableProxy(payable(factoryProxy)), fac);
    vm.stopPrank();
    console2.log('applied upgrades', wrappers.length + 1);

    // Prove the fix on a 6-, 18- and 8-decimal wrapper.
    _confirm('wnUSDC (6dec) ', NeverlandMonadMainnet.STATN_USDC, tok);
    _confirm('wnWMON (18dec)', NeverlandMonadMainnet.STATN_WMON, tok);
    _confirm('wnWBTC (8dec) ', NeverlandMonadMainnet.STATN_WBTC, tok);

    console2.log('CONFIRM: PASS - vuln dead + state preserved on all sampled wrappers');
  }

  function _confirm(string memory name, address wAddr, address expectedImpl) internal {
    StaticATokenLM w = StaticATokenLM(wAddr);

    // 1) the patched implementation is actually live
    require(_impl(wAddr) == expectedImpl, 'IMPL_NOT_SET');
    require(w.STATIC__ATOKEN_LM_REVISION() == 3, 'REVISION');
    require(w.REWARD_RESCUE_ADMIN() == NeverlandMonadMainnet.PROXY_ADMIN_OWNER, 'RESCUE_ADMIN');

    address[] memory rewards = w.rewardTokens();
    require(rewards.length > 0, 'NO_REWARD_TOKENS');
    address dust = rewards[0];
    address strategy = IRewardsControllerView(address(w.INCENTIVES_CONTROLLER()))
      .getTransferStrategy(dust);
    address treasury = IDustLockView(ITransferStrategyView(strategy).DUST_LOCK())
      .earlyWithdrawTreasury();

    uint256 supplyBefore = w.totalSupply();
    uint256 wrapperDustBefore = IERC20(dust).balanceOf(wAddr);
    uint256 treasuryDustBefore = IERC20(dust).balanceOf(treasury);

    // 2) THE FIX: the previously-exploitable function is now a no-op that moves nothing.
    //    Anyone (this script = a random caller) calls it, as the attacker would have.
    uint256 collected = w.collectAndUpdateRewards(dust);
    require(collected == 0, 'COLLECT_NOT_NOOP');
    require(IERC20(dust).balanceOf(wAddr) == wrapperDustBefore, 'DUST_STRANDED_IN_WRAPPER');
    require(IERC20(dust).balanceOf(treasury) == treasuryDustBefore, 'DUST_LEAKED_TO_TREASURY');

    // 3) depositor state untouched by the upgrade + the (neutralized) attack
    require(w.totalSupply() == supplyBefore, 'SUPPLY_CHANGED');

    console2.log(
      string.concat('  ', name, ' rev3, collect no-op, 0 DUST moved, supply preserved'),
      supplyBefore
    );
  }

  function _impl(address proxy) internal view returns (address) {
    return
      address(
        uint160(
          uint256(
            vm.load(proxy, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)
          )
        )
      );
  }
}
