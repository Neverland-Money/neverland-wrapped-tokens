// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {NeverlandMonadMainnet} from '../src/NeverlandAddressBook.sol';

/**
 * @title ExportUpgradeSafeBatch
 * @notice Validates already-deployed StaticATokenLM + StaticATokenFactory implementations supplied
 *         via env and writes a Gnosis Safe Transaction Builder batch JSON containing the
 *         `ProxyAdmin.upgrade(proxy, impl)` calls for all 11 live wrapper proxies plus the factory
 *         proxy.
 *
 * @dev    The emitted JSON is the INPUT to neverland-contracts'
 *         `convert-safe-batch-to-timelock-payload` task (governance lane), which wraps these calls
 *         into a single NeverlandTimelockController batch operation and emits schedule / execute /
 *         cancel Safe batches. The ProxyAdmin owner is the governance timelock (min delay 86400s),
 *         so the batch is NOT executed directly here — it is scheduled/executed via that timelock.
 *
 *         The implementation addresses must already be deployed on Monad and supplied via env.
 *         This script intentionally does not deploy implementations, because a dry-run deployment
 *         would otherwise produce a valid-looking batch that points at non-existent live code.
 *
 * Usage:
 *   NEW_TOKEN_IMPL=0x... NEW_FACTORY_IMPL=0x... \
 *     forge script scripts/ExportUpgradeSafeBatch.s.sol:ExportUpgradeSafeBatch --rpc-url https://rpc.monad.xyz
 *
 * Output: ./reports/wnt-upgrade-safe-batch.json
 */
contract ExportUpgradeSafeBatch is Script {
  // ProxyAdmin.upgrade(address proxy, address implementation)
  bytes4 internal constant UPGRADE_SELECTOR = 0x99a88ec4;
  string internal constant OUT_PATH = './reports/wnt-upgrade-safe-batch.json';
  string internal constant CHAIN_ID = '143'; // Monad mainnet
  bytes32 internal constant EIP1967_ADMIN_SLOT =
    0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
  bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  function run() external {
    require(block.chainid == 143, 'WRONG_CHAIN');

    address proxyAdmin = NeverlandMonadMainnet.PROXY_ADMIN;
    address factoryProxy = NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY;
    require(proxyAdmin != address(0) && factoryProxy != address(0), 'ADDRESS_BOOK');

    address newTokenImpl = vm.envAddress('NEW_TOKEN_IMPL');
    address newFactoryImpl = vm.envAddress('NEW_FACTORY_IMPL');
    _validateImplementations(proxyAdmin, factoryProxy, newTokenImpl, newFactoryImpl);

    // 11 wrapper proxies -> new token impl ; factory proxy -> new factory impl.
    address[] memory proxies = _upgradeProxies();
    _validateProxySet(factoryProxy, proxyAdmin, proxies);
    address[] memory impls = new address[](12);
    for (uint256 i = 0; i < 11; i++) {
      impls[i] = newTokenImpl;
    }
    impls[11] = newFactoryImpl;

    string memory txs = '';
    for (uint256 i = 0; i < proxies.length; i++) {
      require(proxies[i] != address(0), 'PROXY_ZERO');
      bytes memory data = abi.encodeWithSelector(UPGRADE_SELECTOR, proxies[i], impls[i]);
      string memory one = string.concat(
        '{"to":"',
        vm.toString(proxyAdmin),
        '","value":"0","data":"',
        vm.toString(data),
        '","contractMethod":null,"contractInputsValues":null}'
      );
      txs = i == 0 ? one : string.concat(txs, ',', one);
    }

    string memory json = string.concat(
      '{"version":"1.0","chainId":"',
      CHAIN_ID,
      '","meta":{"name":"wrapped-n-tokens implementation upgrade",',
      '"description":"ProxyAdmin.upgrade: 11 wrapper proxies -> new StaticATokenLM impl + factory proxy -> new StaticATokenFactory impl (rewards-claim hardfix + ERC20/ERC721 rescue, revision 3)",',
      '"txBuilderVersion":"1.18.0"},"transactions":[',
      txs,
      ']}'
    );

    vm.writeFile(OUT_PATH, json);

    console2.log('=== wrapped-n-tokens upgrade Safe batch exported ===');
    console2.log('ProxyAdmin (target):      ', proxyAdmin);
    console2.log('New StaticATokenLM impl:  ', newTokenImpl);
    console2.log('New StaticATokenFactory:  ', newFactoryImpl);
    console2.log('Upgrade calls in batch:   ', proxies.length);
    console2.log('Safe batch written to:    ', OUT_PATH);
    console2.log(
      'Next: feed it to neverland-contracts convert-safe-batch-to-timelock-payload (lane=governance)'
    );
  }

  function _validateImplementations(
    address proxyAdmin,
    address factoryProxy,
    address newTokenImpl,
    address newFactoryImpl
  ) internal view {
    _requireCode(newTokenImpl, 'TOKEN_IMPL_NO_CODE');
    _requireCode(newFactoryImpl, 'FACTORY_IMPL_NO_CODE');

    StaticATokenLM tokenImpl = StaticATokenLM(newTokenImpl);
    require(address(tokenImpl.POOL()) == NeverlandMonadMainnet.POOL, 'TOKEN_IMPL_POOL');
    require(
      address(tokenImpl.INCENTIVES_CONTROLLER()) == NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER,
      'TOKEN_IMPL_REWARDS'
    );
    require(tokenImpl.STATIC__ATOKEN_LM_REVISION() == 3, 'TOKEN_IMPL_REVISION');

    StaticATokenFactory factoryImpl = StaticATokenFactory(newFactoryImpl);
    require(address(factoryImpl.POOL()) == NeverlandMonadMainnet.POOL, 'FACTORY_IMPL_POOL');
    require(factoryImpl.ADMIN() == proxyAdmin, 'FACTORY_IMPL_ADMIN');
    require(
      address(factoryImpl.TRANSPARENT_PROXY_FACTORY()) ==
        NeverlandMonadMainnet.TRANSPARENT_PROXY_FACTORY,
      'FACTORY_IMPL_PROXY_FACTORY'
    );
    require(factoryImpl.STATIC_A_TOKEN_IMPL() == newTokenImpl, 'FACTORY_IMPL_TOKEN_IMPL');

    require(newFactoryImpl != _readImplementation(factoryProxy), 'FACTORY_IMPL_UNCHANGED');
    require(
      newTokenImpl != _readImplementation(NeverlandMonadMainnet.STATN_USDC),
      'TOKEN_IMPL_UNCHANGED'
    );
  }

  function _validateProxySet(
    address factoryProxy,
    address proxyAdmin,
    address[] memory proxies
  ) internal view {
    address[] memory factoryTokens = StaticATokenFactory(factoryProxy).getStaticATokens();
    require(factoryTokens.length == 11, 'FACTORY_TOKEN_COUNT');
    require(proxies.length == 12, 'PROXY_COUNT');
    require(proxies[11] == factoryProxy, 'FACTORY_PROXY_MISSING');

    for (uint256 i = 0; i < proxies.length; i++) {
      require(proxies[i] != address(0), 'PROXY_ZERO');
      _requireCode(proxies[i], 'PROXY_NO_CODE');
      require(_readProxyAdmin(proxies[i]) == proxyAdmin, 'PROXY_ADMIN');
    }

    for (uint256 i = 0; i < 11; i++) {
      bool found;
      for (uint256 j = 0; j < factoryTokens.length; j++) {
        if (proxies[i] == factoryTokens[j]) {
          found = true;
          break;
        }
      }
      require(found, 'PROXY_NOT_IN_FACTORY');
    }
  }

  function _upgradeProxies() internal pure returns (address[] memory proxies) {
    proxies = new address[](12);
    proxies[0] = NeverlandMonadMainnet.STATN_WMON;
    proxies[1] = NeverlandMonadMainnet.STATN_USDC;
    proxies[2] = NeverlandMonadMainnet.STATN_USDT0;
    proxies[3] = NeverlandMonadMainnet.STATN_WBTC;
    proxies[4] = NeverlandMonadMainnet.STATN_WETH;
    proxies[5] = NeverlandMonadMainnet.STATN_SMON;
    proxies[6] = NeverlandMonadMainnet.STATN_SHMON;
    proxies[7] = NeverlandMonadMainnet.STATN_GMON;
    proxies[8] = NeverlandMonadMainnet.STATN_AUSD;
    proxies[9] = NeverlandMonadMainnet.STATN_EARNAUSD;
    proxies[10] = NeverlandMonadMainnet.STATN_LOAZND;
    proxies[11] = NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY;
  }

  function _requireCode(address target, string memory error) internal view {
    require(target != address(0) && target.code.length > 0, error);
  }

  function _readProxyAdmin(address proxy) internal view returns (address) {
    return address(uint160(uint256(vm.load(proxy, EIP1967_ADMIN_SLOT))));
  }

  function _readImplementation(address proxy) internal view returns (address) {
    return address(uint160(uint256(vm.load(proxy, EIP1967_IMPLEMENTATION_SLOT))));
  }
}
