// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {ERC20} from '../src/ERC20.sol';
import {IAToken} from '../src/interfaces/IAToken.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';

contract MockPool {
  uint256 public normalizedIncome = 1e27;

  function setNormalizedIncome(uint256 value) external {
    normalizedIncome = value;
  }

  function getReserveNormalizedIncome(address) external view returns (uint256) {
    return normalizedIncome;
  }
}

contract MockERC20 is ERC20 {
  constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract MockAToken is MockERC20, IAToken {
  address internal _pool;
  address internal _underlying;
  address internal _incentives;

  constructor(address pool_, address underlying_)
    MockERC20('MockAToken', 'mAT', 18)
  {
    _pool = pool_;
    _underlying = underlying_;
  }

  function POOL() external view returns (address) {
    return _pool;
  }

  function getIncentivesController() external view returns (address) {
    return _incentives;
  }

  function setIncentivesController(address incentives) external {
    _incentives = incentives;
  }

  function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
    return _underlying;
  }

  function scaledTotalSupply() external view returns (uint256) {
    return totalSupply;
  }
}

contract MockRewardsController {
  uint256 public constant BPS = 10_000;

  address public immutable rewardToken;
  address public immutable asset;
  address public immutable treasury;
  uint256 public immutable penaltyBps;

  uint256 public assetIndex;
  mapping(address => address) internal _claimers;

  constructor(address rewardToken_, address asset_, address treasury_, uint256 penaltyBps_) {
    rewardToken = rewardToken_;
    asset = asset_;
    treasury = treasury_;
    penaltyBps = penaltyBps_;
  }

  function setClaimer(address user, address claimer) external {
    _claimers[user] = claimer;
  }

  function getClaimer(address user) external view returns (address) {
    return _claimers[user];
  }

  function setAssetIndex(uint256 index) external {
    assetIndex = index;
  }

  function getRewardsByAsset(address asset_) external view returns (address[] memory) {
    require(asset_ == asset, 'ASSET');
    address[] memory rewards = new address[](1);
    rewards[0] = rewardToken;
    return rewards;
  }

  function getAssetIndex(address asset_, address reward) external view returns (uint256, uint256) {
    require(asset_ == asset, 'ASSET');
    require(reward == rewardToken, 'REWARD');
    return (0, assetIndex);
  }

  function getUserRewards(
    address[] calldata,
    address,
    address
  ) external pure returns (uint256) {
    return 0;
  }

  function claimRewards(
    address[] calldata assets,
    uint256 amount,
    address to,
    address reward
  ) external returns (uint256) {
    return claimRewards(assets, amount, to, reward, 0, 0);
  }

  function claimRewards(
    address[] calldata assets,
    uint256 amount,
    address to,
    address reward,
    uint256 lockTime,
    uint256 tokenId
  ) public returns (uint256) {
    require(assets.length == 1 && assets[0] == asset, 'ASSET');
    require(reward == rewardToken, 'REWARD');

    uint256 claimAmount = amount;
    uint256 available = MockERC20(rewardToken).balanceOf(address(this));
    if (amount == type(uint256).max) {
      claimAmount = available;
    } else if (claimAmount > available) {
      claimAmount = available;
    }

    if (lockTime == 0 && tokenId == 0 && penaltyBps > 0) {
      uint256 penalty = (claimAmount * penaltyBps) / BPS;
      MockERC20(rewardToken).transfer(to, claimAmount - penalty);
      if (penalty > 0) {
        MockERC20(rewardToken).transfer(treasury, penalty);
      }
    } else {
      MockERC20(rewardToken).transfer(to, claimAmount);
    }

    return claimAmount;
  }
}

contract StaticATokenLMDustRewardsTest is Test {
  uint256 internal constant PENALTY_BPS = 5_000;
  uint256 internal constant REWARD_INDEX = 1e18;
  uint256 internal constant USER_BALANCE = 100e18;

  address internal constant USER = address(0x1);
  address internal constant CLAIMER = address(0x2);
  address internal constant TREASURY = address(0x3);

  MockPool internal pool;
  MockERC20 internal underlying;
  MockAToken internal aToken;
  MockERC20 internal dust;
  MockRewardsController internal controller;
  StaticATokenLM internal staticATokenLM;

  function setUp() public {
    pool = new MockPool();
    underlying = new MockERC20('Underlying', 'UND', 18);
    aToken = new MockAToken(address(pool), address(underlying));
    dust = new MockERC20('Dust', 'DUST', 18);
    controller = new MockRewardsController(address(dust), address(aToken), TREASURY, PENALTY_BPS);

    StaticATokenLM impl = new StaticATokenLM(
      IPool(address(pool)),
      IRewardsController(address(controller))
    );
    bytes memory initData = abi.encodeWithSelector(
      StaticATokenLM.initialize.selector,
      address(aToken),
      'Static aToken',
      'stata'
    );
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(impl),
      address(0xBEEF),
      initData
    );
    staticATokenLM = StaticATokenLM(address(proxy));

    aToken.mint(USER, USER_BALANCE);
    vm.startPrank(USER);
    aToken.approve(address(staticATokenLM), USER_BALANCE);
    staticATokenLM.deposit(USER_BALANCE, USER, 0, false);
    vm.stopPrank();
  }

  function _accrueRewards() internal returns (uint256) {
    controller.setAssetIndex(REWARD_INDEX);
    return staticATokenLM.getClaimableRewards(USER, address(dust));
  }

  function test_claimRewards_liquidPenalty_direct() public {
    uint256 userReward = _accrueRewards();
    assertEq(userReward, USER_BALANCE);

    dust.mint(address(controller), userReward);

    address[] memory rewards = new address[](1);
    rewards[0] = address(dust);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
    assertEq(dust.balanceOf(address(staticATokenLM)), 0);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_claimRewardsWithLock_fullAmount() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    address[] memory rewards = new address[](1);
    rewards[0] = address(dust);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, rewards, 7 days, 0);

    assertEq(dust.balanceOf(USER), userReward);
    assertEq(dust.balanceOf(TREASURY), 0);
    assertEq(dust.balanceOf(address(staticATokenLM)), 0);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_claimRewardsToSelfWithLock_fullAmount() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    address[] memory rewards = new address[](1);
    rewards[0] = address(dust);

    vm.prank(USER);
    staticATokenLM.claimRewardsToSelfWithLock(rewards, 30 days, 0);

    assertEq(dust.balanceOf(USER), userReward);
    assertEq(dust.balanceOf(TREASURY), 0);
    assertEq(dust.balanceOf(address(staticATokenLM)), 0);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_claimRewardsOnBehalfWithLock_authorizedClaimer() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);
    controller.setClaimer(USER, CLAIMER);

    address[] memory rewards = new address[](1);
    rewards[0] = address(dust);

    vm.prank(CLAIMER);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, USER, rewards, 14 days, 0);

    assertEq(dust.balanceOf(USER), userReward);
    assertEq(dust.balanceOf(TREASURY), 0);
    assertEq(dust.balanceOf(address(staticATokenLM)), 0);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_collectAndUpdateRewards_balanceDelta() public {
    uint256 amount = 100e18;
    dust.mint(address(controller), amount);

    uint256 claimed = staticATokenLM.collectAndUpdateRewards(address(dust));
    uint256 penalty = (amount * PENALTY_BPS) / 10_000;

    assertEq(claimed, amount - penalty);
    assertEq(dust.balanceOf(address(staticATokenLM)), amount - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
  }

  function test_claimRewards_partialFunding_keepsUnclaimed() public {
    uint256 userReward = _accrueRewards();
    uint256 partialAmount = userReward / 2;
    dust.mint(address(controller), partialAmount);

    address[] memory rewards = new address[](1);
    rewards[0] = address(dust);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), userReward - partialAmount);

    dust.mint(address(controller), userReward - partialAmount);
    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_claimRewardsOnBehalf_receiverDiffers_updatesUserAccounting() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);
    controller.setClaimer(USER, CLAIMER);

    address receiver = address(0x9);
    address[] memory rewards = new address[](1);
    rewards[0] = address(dust);

    vm.prank(CLAIMER);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, receiver, rewards, 0, 0);

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(receiver), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_collectAndUpdateRewards_balanceDelta_withExistingBalance() public {
    uint256 existing = 10e18;
    dust.mint(address(staticATokenLM), existing);

    uint256 amount = 80e18;
    dust.mint(address(controller), amount);

    uint256 claimed = staticATokenLM.collectAndUpdateRewards(address(dust));
    uint256 penalty = (amount * PENALTY_BPS) / 10_000;

    assertEq(claimed, amount - penalty);
    assertEq(dust.balanceOf(address(staticATokenLM)), existing + amount - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
  }
}
