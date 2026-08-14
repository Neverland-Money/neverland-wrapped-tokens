// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from 'forge-std/Script.sol';
import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {console2} from 'forge-std/console2.sol';

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {ProxyAdmin} from 'solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';

import {ERC20} from '../src/ERC20.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {NeverlandMonadMainnet} from '../src/NeverlandAddressBook.sol';

interface IDustRewardsControllerForkView {
  function getTransferStrategy(address reward) external view returns (address);
}

interface IDustLockTransferStrategyForkView {
  function DUST_LOCK() external view returns (address);
}

interface IDustLockForkView {
  function earlyWithdrawTreasury() external view returns (address);
}

contract MintableRescueToken is ERC20 {
  constructor() ERC20('Fork Rescue Token', 'FRT', 18) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

/**
 * @notice Fork-only proof that the deployed implementation pair can upgrade the live proxy set and
 *         preserve/operate wnUSDC after the upgrade.
 *
 * Usage:
 *   NEW_TOKEN_IMPL=0x... NEW_FACTORY_IMPL=0x... \
 *     forge script scripts/SimulateUpgradeFork.s.sol:SimulateUpgradeFork --rpc-url monad -vv
 */
contract SimulateUpgradeFork is Script {
  using stdStorage for StdStorage;

  bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
  uint256 internal constant PRE_UPGRADE_DEPOSIT = 1_000e6;
  uint256 internal constant POST_UPGRADE_DEPOSIT = 25e6;
  uint256 internal constant POST_UPGRADE_WITHDRAW = 10e6;
  uint256 internal constant RESCUE_AMOUNT = 123e18;

  function run() external {
    require(block.chainid == 143, 'WRONG_CHAIN');

    address newTokenImpl = vm.envAddress('NEW_TOKEN_IMPL');
    address newFactoryImpl = vm.envAddress('NEW_FACTORY_IMPL');
    _requireCode(newTokenImpl, 'TOKEN_IMPL_NO_CODE');
    _requireCode(newFactoryImpl, 'FACTORY_IMPL_NO_CODE');

    StaticATokenLM wrapper = StaticATokenLM(NeverlandMonadMainnet.STATN_USDC);
    StaticATokenFactory factory = StaticATokenFactory(NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY);
    address user = vm.addr(uint256(0xA11CE));
    address rescueReceiver = vm.addr(uint256(0xB0B));

    console2.log('=== wrapped-n-tokens fork upgrade simulation ===');
    console2.log('block', block.number);
    console2.log('wnUSDC', address(wrapper));
    console2.log('user', user);
    console2.log('newTokenImpl', newTokenImpl);
    console2.log('newFactoryImpl', newFactoryImpl);

    _proveFactoryPreState(factory, address(wrapper));
    uint256 preUpgradeShares = _seedUserDeposit(wrapper, user);

    uint256 userStaticBefore = wrapper.balanceOf(user);
    uint256 totalSupplyBefore = wrapper.totalSupply();
    uint256 totalAssetsBefore = wrapper.totalAssets();
    uint256 rewardCountBefore = wrapper.rewardTokens().length;
    require(userStaticBefore == preUpgradeShares, 'PRE_BALANCE_MISMATCH');

    address[] memory upgradedProxies = _applyUpgrades(newTokenImpl, newFactoryImpl);
    _assertImplementations(upgradedProxies, newTokenImpl, newFactoryImpl);

    require(wrapper.balanceOf(user) == userStaticBefore, 'USER_BALANCE_CHANGED');
    require(wrapper.totalSupply() == totalSupplyBefore, 'TOTAL_SUPPLY_CHANGED');
    require(wrapper.totalAssets() == totalAssetsBefore, 'TOTAL_ASSETS_CHANGED');
    require(wrapper.rewardTokens().length == rewardCountBefore, 'REWARD_COUNT_CHANGED');
    require(
      factory.getStaticAToken(NeverlandMonadMainnet.USDC) == address(wrapper),
      'FACTORY_USDC'
    );

    console2.log('post-upgrade balance preserved', userStaticBefore);
    _proveDepositWithdraw(wrapper, user);
    _proveClaimRoutes(wrapper, user);
    _proveRescueGated(wrapper, user, rescueReceiver);

    console2.log('Simulation complete: PASS');
  }

  function _proveFactoryPreState(StaticATokenFactory factory, address wrapper) internal view {
    address[] memory staticATokens = factory.getStaticATokens();
    require(staticATokens.length > 0, 'FACTORY_TOKEN_COUNT');
    require(factory.getStaticAToken(NeverlandMonadMainnet.USDC) == wrapper, 'FACTORY_USDC_PRE');
    console2.log('live wrapper count', staticATokens.length);
  }

  function _seedUserDeposit(
    StaticATokenLM wrapper,
    address user
  ) internal returns (uint256 shares) {
    IERC20 usdc = IERC20(NeverlandMonadMainnet.USDC);
    _dealERC20(NeverlandMonadMainnet.USDC, user, PRE_UPGRADE_DEPOSIT + POST_UPGRADE_DEPOSIT);
    vm.deal(user, 10 ether);

    vm.startPrank(user);
    usdc.approve(address(wrapper), type(uint256).max);
    shares = wrapper.deposit(PRE_UPGRADE_DEPOSIT, user, 0, true);
    vm.stopPrank();

    require(shares > 0, 'NO_PRE_UPGRADE_SHARES');
    console2.log('pre-upgrade deposit shares', shares);
  }

  /// @dev Returns the proxy set as it stood BEFORE the upgrade, for the post-conditions to use.
  function _applyUpgrades(
    address newTokenImpl,
    address newFactoryImpl
  ) internal returns (address[] memory proxies) {
    ProxyAdmin proxyAdmin = ProxyAdmin(NeverlandMonadMainnet.PROXY_ADMIN);
    proxies = _upgradeProxies();
    uint256 wrapperCount = proxies.length - 1;

    vm.startPrank(NeverlandMonadMainnet.PROXY_ADMIN_OWNER);
    for (uint256 i = 0; i < wrapperCount; i++) {
      proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(proxies[i])), newTokenImpl);
    }
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(proxies[wrapperCount])), newFactoryImpl);
    vm.stopPrank();

    console2.log('applied ProxyAdmin.upgrade calls', proxies.length);
  }

  /**
   * @dev Takes the pre-upgrade snapshot rather than re-reading the registry. Re-reading would source
   *      the post-condition from the factory implementation under test: one that enumerated a subset
   *      would shrink this loop and pass, which is the regression this proof exists to catch. The
   *      registry is then compared against the snapshot so a changed enumeration fails loudly.
   */
  function _assertImplementations(
    address[] memory proxies,
    address newTokenImpl,
    address newFactoryImpl
  ) internal view {
    uint256 wrapperCount = proxies.length - 1;
    for (uint256 i = 0; i < wrapperCount; i++) {
      require(_readImplementation(proxies[i]) == newTokenImpl, 'TOKEN_IMPL_NOT_SET');
    }
    require(_readImplementation(proxies[wrapperCount]) == newFactoryImpl, 'FACTORY_IMPL_NOT_SET');

    address[] memory postUpgrade = StaticATokenFactory(proxies[wrapperCount]).getStaticATokens();
    require(postUpgrade.length == wrapperCount, 'REGISTRY_LENGTH_CHANGED');
    for (uint256 i = 0; i < wrapperCount; i++) {
      require(postUpgrade[i] == proxies[i], 'REGISTRY_ENTRY_CHANGED');
    }
  }

  function _proveDepositWithdraw(StaticATokenLM wrapper, address user) internal {
    IERC20 usdc = IERC20(NeverlandMonadMainnet.USDC);
    uint256 underlyingBefore = usdc.balanceOf(user);
    uint256 staticBefore = wrapper.balanceOf(user);

    vm.prank(user);
    uint256 shares = wrapper.deposit(POST_UPGRADE_DEPOSIT, user, 0, true);
    require(shares > 0, 'NO_POST_UPGRADE_SHARES');
    require(wrapper.balanceOf(user) == staticBefore + shares, 'POST_DEPOSIT_BALANCE');

    vm.prank(user);
    uint256 burnedShares = wrapper.withdraw(POST_UPGRADE_WITHDRAW, user, user);

    require(burnedShares > 0 && burnedShares <= shares, 'WITHDRAW_SHARES');
    require(
      usdc.balanceOf(user) == underlyingBefore - POST_UPGRADE_DEPOSIT + POST_UPGRADE_WITHDRAW,
      'WITHDRAW_UNDERLYING'
    );

    console2.log('post-upgrade deposit shares', shares);
    console2.log('post-upgrade withdraw shares', burnedShares);
  }

  function _proveClaimRoutes(StaticATokenLM wrapper, address user) internal {
    address[] memory rewards = wrapper.rewardTokens();
    require(rewards.length > 0, 'NO_REWARDS');
    address dust = rewards[0];
    address strategy = IDustRewardsControllerForkView(address(wrapper.INCENTIVES_CONTROLLER()))
      .getTransferStrategy(dust);
    address dustLock = IDustLockTransferStrategyForkView(strategy).DUST_LOCK();
    address treasury = IDustLockForkView(dustLock).earlyWithdrawTreasury();

    uint256 claimable = wrapper.getClaimableRewards(user, dust);
    uint256 rounds;
    while (claimable == 0 && rounds < 8) {
      _advanceTime(1 days);
      claimable = wrapper.getClaimableRewards(user, dust);
      rounds++;
    }
    require(claimable > 0, 'NO_CLAIMABLE_REWARDS');

    uint256 userBefore = IERC20(dust).balanceOf(user);
    uint256 treasuryBefore = IERC20(dust).balanceOf(treasury);
    vm.prank(user);
    wrapper.claimRewards(user, _singleReward(dust));

    uint256 expectedTreasury = claimable / 2;
    uint256 expectedUser = claimable - expectedTreasury;
    require(IERC20(dust).balanceOf(user) - userBefore == expectedUser, 'CLAIM_USER_DELTA');
    require(
      IERC20(dust).balanceOf(treasury) - treasuryBefore == expectedTreasury,
      'CLAIM_TREASURY_DELTA'
    );
    require(wrapper.getUnclaimedRewards(user, dust) == 0, 'UNCLAIMED_AFTER_CLAIM');

    console2.log('post-upgrade liquid claim amount', claimable);
    console2.log('post-upgrade liquid claim user', expectedUser);
    console2.log('post-upgrade liquid claim treasury', expectedTreasury);
  }

  function _proveRescueGated(
    StaticATokenLM wrapper,
    address user,
    address rescueReceiver
  ) internal {
    MintableRescueToken rescueToken = new MintableRescueToken();
    rescueToken.mint(address(wrapper), RESCUE_AMOUNT);

    vm.expectRevert();
    vm.prank(user);
    wrapper.rescueERC20(address(rescueToken), rescueReceiver);

    address rescueAdmin = wrapper.REWARD_RESCUE_ADMIN();
    require(rescueAdmin == NeverlandMonadMainnet.PROXY_ADMIN_OWNER, 'RESCUE_ADMIN');
    address aToken = address(wrapper.aToken());

    vm.expectRevert();
    vm.prank(rescueAdmin);
    wrapper.rescueERC20(aToken, rescueReceiver);

    vm.prank(rescueAdmin);
    uint256 rescued = wrapper.rescueERC20(address(rescueToken), rescueReceiver);
    require(rescued == RESCUE_AMOUNT, 'RESCUE_AMOUNT');
    require(rescueToken.balanceOf(rescueReceiver) == RESCUE_AMOUNT, 'RESCUE_RECEIVER');

    console2.log('rescue admin', rescueAdmin);
    console2.log('rescued mock ERC20', rescued);
  }

  /**
   * @dev Read from the factory registry rather than hardcoded, so this simulation always covers the
   *      same proxy set the exported governance batch will, including wrappers created after this
   *      script was last edited.
   */
  function _upgradeProxies() internal view returns (address[] memory proxies) {
    address factoryProxy = NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY;
    address[] memory wrappers = StaticATokenFactory(factoryProxy).getStaticATokens();
    require(wrappers.length > 0, 'NO_WRAPPERS');

    // Gate on the same condition ExportUpgradeSafeBatch does, so this simulation cannot pass for a
    // wrapper set the export path refuses.
    for (uint256 i = 0; i < wrappers.length; i++) {
      require(
        NeverlandMonadMainnet.isPinnedStaticAToken(wrappers[i]),
        'WRAPPER_NOT_IN_ADDRESS_BOOK'
      );
    }

    proxies = new address[](wrappers.length + 1);
    for (uint256 i = 0; i < wrappers.length; i++) {
      proxies[i] = wrappers[i];
    }
    proxies[wrappers.length] = factoryProxy;
  }

  function _singleReward(address reward) internal pure returns (address[] memory rewards) {
    rewards = new address[](1);
    rewards[0] = reward;
  }

  function _advanceTime(uint256 secondsToAdvance) internal {
    vm.warp(block.timestamp + secondsToAdvance);
    vm.roll(block.number + (secondsToAdvance / 12) + 1);
  }

  function _dealERC20(address token, address to, uint256 amount) internal {
    stdstore.target(token).sig(IERC20.balanceOf.selector).with_key(to).checked_write(amount);
  }

  function _readImplementation(address proxy) internal view returns (address) {
    return address(uint160(uint256(vm.load(proxy, EIP1967_IMPLEMENTATION_SLOT))));
  }

  function _requireCode(address target, string memory error) internal view {
    require(target != address(0) && target.code.length > 0, error);
  }
}
