// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';

import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {NeverlandMonadMainnet} from '../src/NeverlandAddressBook.sol';

interface IOwnableView {
  function owner() external view returns (address);
}

/**
 * @title DeployUpgradeImplementations
 * @notice Deploys only the new wrapped-n-tokens implementations needed for the Monad production
 *         upgrade. It does not deploy proxies, create wrappers, or execute upgrades.
 *
 * Usage:
 *   forge script scripts/DeployUpgradeImplementations.s.sol:DeployUpgradeImplementations \
 *     --rpc-url monad --broadcast --private-key $PRIVATE_KEY -vvv
 *
 * Then copy the printed NEW_TOKEN_IMPL / NEW_FACTORY_IMPL values into ExportUpgradeSafeBatch.
 */
contract DeployUpgradeImplementations is Script {
  function run() external {
    _preflight();

    vm.startBroadcast();
    (, address deployer, ) = vm.readCallers();

    StaticATokenLM tokenImpl = new StaticATokenLM(
      IPool(NeverlandMonadMainnet.POOL),
      IRewardsController(NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER)
    );

    StaticATokenFactory factoryImpl = new StaticATokenFactory(
      IPool(NeverlandMonadMainnet.POOL),
      NeverlandMonadMainnet.PROXY_ADMIN,
      ITransparentProxyFactory(NeverlandMonadMainnet.TRANSPARENT_PROXY_FACTORY),
      address(tokenImpl)
    );

    vm.stopBroadcast();

    _validate(address(tokenImpl), address(factoryImpl));
    _printSummary(deployer, address(tokenImpl), address(factoryImpl));
  }

  function _preflight() internal view {
    if (!vm.envOr('SKIP_CHAINID_CHECK', false)) {
      require(block.chainid == 143, 'WRONG_CHAIN');
    }

    _requireCode(NeverlandMonadMainnet.POOL, 'POOL_NO_CODE');
    _requireCode(NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER, 'REWARDS_CONTROLLER_NO_CODE');
    _requireCode(NeverlandMonadMainnet.PROXY_ADMIN, 'PROXY_ADMIN_NO_CODE');
    _requireCode(NeverlandMonadMainnet.TRANSPARENT_PROXY_FACTORY, 'PROXY_FACTORY_NO_CODE');
    _requireCode(NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY, 'FACTORY_PROXY_NO_CODE');

    if (!vm.envOr('SKIP_PROXY_ADMIN_OWNER_CHECK', false)) {
      address owner = IOwnableView(NeverlandMonadMainnet.PROXY_ADMIN).owner();
      require(owner == NeverlandMonadMainnet.PROXY_ADMIN_OWNER, 'PROXY_ADMIN_OWNER');
    }
  }

  function _validate(address tokenImpl, address factoryImpl) internal view {
    _requireCode(tokenImpl, 'TOKEN_IMPL_NO_CODE');
    _requireCode(factoryImpl, 'FACTORY_IMPL_NO_CODE');

    StaticATokenLM token = StaticATokenLM(tokenImpl);
    require(address(token.POOL()) == NeverlandMonadMainnet.POOL, 'TOKEN_IMPL_POOL');
    require(
      address(token.INCENTIVES_CONTROLLER()) == NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER,
      'TOKEN_IMPL_REWARDS'
    );
    require(token.STATIC__ATOKEN_LM_REVISION() == 3, 'TOKEN_IMPL_REVISION');

    StaticATokenFactory factory = StaticATokenFactory(factoryImpl);
    require(address(factory.POOL()) == NeverlandMonadMainnet.POOL, 'FACTORY_IMPL_POOL');
    require(factory.ADMIN() == NeverlandMonadMainnet.PROXY_ADMIN, 'FACTORY_IMPL_ADMIN');
    require(
      address(factory.TRANSPARENT_PROXY_FACTORY()) ==
        NeverlandMonadMainnet.TRANSPARENT_PROXY_FACTORY,
      'FACTORY_IMPL_PROXY_FACTORY'
    );
    require(factory.STATIC_A_TOKEN_IMPL() == tokenImpl, 'FACTORY_IMPL_TOKEN_IMPL');
  }

  function _printSummary(address deployer, address tokenImpl, address factoryImpl) internal pure {
    console2.log('=== wrapped-n-tokens implementations deployed ===');
    console2.log('Deployer:                         ', deployer);
    console2.log('StaticATokenLM implementation:     ', tokenImpl);
    console2.log('StaticATokenFactory implementation:', factoryImpl);
    console2.log('');
    console2.log('Use these only from a confirmed --broadcast run:');
    console2.log(string.concat('export NEW_TOKEN_IMPL=', vm.toString(tokenImpl)));
    console2.log(string.concat('export NEW_FACTORY_IMPL=', vm.toString(factoryImpl)));
    console2.log('');
    console2.log(
      string.concat(
        'NEW_TOKEN_IMPL=',
        vm.toString(tokenImpl),
        ' NEW_FACTORY_IMPL=',
        vm.toString(factoryImpl),
        ' forge script scripts/ExportUpgradeSafeBatch.s.sol:ExportUpgradeSafeBatch --rpc-url monad'
      )
    );
  }

  function _requireCode(address target, string memory error) internal view {
    require(target != address(0) && target.code.length > 0, error);
  }
}
