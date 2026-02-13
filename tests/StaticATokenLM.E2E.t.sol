// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {ERC20} from '../src/ERC20.sol';
import {IAToken} from '../src/interfaces/IAToken.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';
import {StaticATokenErrors} from '../src/StaticATokenErrors.sol';

contract E2EPool {
  uint256 public normalizedIncome = 1e27;

  function setNormalizedIncome(uint256 value) external {
    normalizedIncome = value;
  }

  function getReserveNormalizedIncome(address) external view returns (uint256) {
    return normalizedIncome;
  }
}

contract E2EToken is ERC20 {
  constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol, _decimals) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract E2EAToken is E2EToken, IAToken {
  address internal _pool;
  address internal _underlying;

  constructor(address pool_, address underlying_) E2EToken('E2EAToken', 'eAT', 18) {
    _pool = pool_;
    _underlying = underlying_;
  }

  function POOL() external view returns (address) {
    return _pool;
  }

  function getIncentivesController() external pure returns (address) {
    return address(0);
  }

  function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
    return _underlying;
  }

  function scaledTotalSupply() external view returns (uint256) {
    return totalSupply;
  }
}

contract E2EDustLock {
  struct Lock {
    uint256 amount;
    uint256 end;
    bool isPermanent;
    address owner;
  }

  address public immutable token;
  address public immutable treasury;
  uint256 public immutable penaltyBps;
  uint256 public nextId = 1;

  mapping(uint256 => Lock) public locks;

  constructor(address token_, address treasury_, uint256 penaltyBps_) {
    token = token_;
    treasury = treasury_;
    penaltyBps = penaltyBps_;
  }

  function earlyWithdrawPenalty() external view returns (uint256) {
    return penaltyBps;
  }

  function earlyWithdrawTreasury() external view returns (address) {
    return treasury;
  }

  function ownerOf(uint256 tokenId) external view returns (address) {
    return locks[tokenId].owner;
  }

  function createLockFor(uint256 amount, uint256 lockTime, address to) external returns (uint256 tokenId) {
    tokenId = nextId++;
    locks[tokenId] = Lock({
      amount: amount,
      end: block.timestamp + lockTime,
      isPermanent: false,
      owner: to
    });
  }

  function createLockPermanentFor(uint256 amount, uint256 lockTime, address to)
    external
    returns (uint256 tokenId)
  {
    tokenId = nextId++;
    locks[tokenId] = Lock({amount: amount, end: lockTime, isPermanent: true, owner: to});
  }

  function depositFor(uint256 tokenId, uint256 amount) external {
    Lock storage lock = locks[tokenId];
    require(lock.owner != address(0), 'NO_LOCK');
    lock.amount += amount;
  }

  function lockAmount(uint256 tokenId) external view returns (uint256) {
    return locks[tokenId].amount;
  }

  function isPermanent(uint256 tokenId) external view returns (bool) {
    return locks[tokenId].isPermanent;
  }
}

interface IE2ETransferStrategy {
  function performTransfer(
    address to,
    address reward,
    uint256 amount,
    uint256 lockTime,
    uint256 tokenId
  ) external returns (bool);
}

contract E2EFeeTransferStrategy is IE2ETransferStrategy {
  address public immutable incentivesController;
  uint256 public immutable feeBps;

  constructor(address controller, uint256 feeBps_) {
    incentivesController = controller;
    feeBps = feeBps_;
  }

  function performTransfer(
    address to,
    address reward,
    uint256 amount,
    uint256,
    uint256
  ) external returns (bool) {
    require(msg.sender == incentivesController, 'ONLY_CONTROLLER');
    if (amount == 0) return true;
    uint256 fee = (amount * feeBps) / 10_000;
    E2EToken(reward).transferFrom(incentivesController, to, amount - fee);
    return true;
  }
}

contract E2EDustLockTransferStrategy {
  uint256 internal constant BPS = 10_000;

  address public immutable incentivesController;
  E2EToken public immutable dust;
  E2EDustLock public immutable dustLock;

  constructor(address controller, address dustToken, address lock) {
    incentivesController = controller;
    dust = E2EToken(dustToken);
    dustLock = E2EDustLock(lock);
  }

  function performTransfer(
    address to,
    address reward,
    uint256 amount,
    uint256 lockTime,
    uint256 tokenId
  ) external returns (bool) {
    require(msg.sender == incentivesController, 'ONLY_CONTROLLER');
    require(reward == address(dust), 'INVALID_REWARD');
    if (amount == 0) return true;

    if (tokenId > 0) {
      require(dustLock.ownerOf(tokenId) == to, 'NOT_OWNER');
      dust.transferFrom(incentivesController, address(dustLock), amount);
      dustLock.depositFor(tokenId, amount);
      return true;
    }

    if (lockTime > 0) {
      dust.transferFrom(incentivesController, address(dustLock), amount);
      if (lockTime == type(uint256).max) {
        dustLock.createLockPermanentFor(amount, lockTime, to);
      } else {
        dustLock.createLockFor(amount, lockTime, to);
      }
      return true;
    }

    uint256 penalty = (amount * dustLock.earlyWithdrawPenalty()) / BPS;
    dust.transferFrom(incentivesController, to, amount - penalty);
    if (penalty > 0) {
      dust.transferFrom(incentivesController, dustLock.earlyWithdrawTreasury(), penalty);
    }
    return true;
  }
}

contract E2ETransferStrategy is IE2ETransferStrategy {
  address public immutable incentivesController;

  constructor(address controller) {
    incentivesController = controller;
  }

  function performTransfer(
    address to,
    address reward,
    uint256 amount,
    uint256,
    uint256
  ) external returns (bool) {
    require(msg.sender == incentivesController, 'ONLY_CONTROLLER');
    if (amount == 0) return true;
    E2EToken(reward).transferFrom(incentivesController, to, amount);
    return true;
  }
}

contract E2EReentrantStrategy is IE2ETransferStrategy {
  address public immutable incentivesController;
  StaticATokenLM public immutable wrapper;
  address public immutable user;
  address public immutable rewardToken;
  bool public entered;
  bool public transferred;

  constructor(address controller, StaticATokenLM wrapper_, address user_, address rewardToken_) {
    incentivesController = controller;
    wrapper = wrapper_;
    user = user_;
    rewardToken = rewardToken_;
  }

  function performTransfer(
    address to,
    address reward,
    uint256 amount,
    uint256,
    uint256
  ) external returns (bool) {
    require(msg.sender == incentivesController, 'ONLY_CONTROLLER');
    if (!entered) {
      entered = true;
      address[] memory rewards = new address[](1);
      rewards[0] = rewardToken;
      wrapper.claimRewardsOnBehalfWithLock(user, user, rewards, 0, 0);
    }
    if (!transferred) {
      transferred = true;
      E2EToken(reward).transferFrom(incentivesController, to, amount);
    }
    return true;
  }
}

contract E2ERewardsController {
  error InvalidToAddress();

  address public immutable rewardToken;
  address public immutable asset;
  mapping(address => address) internal _claimers;
  mapping(address => address) internal _transferStrategies;
  address[] internal _rewardsList;
  mapping(address => bool) internal _isReward;
  mapping(address => uint256) internal _assetIndexes;

  constructor(address rewardToken_, address asset_) {
    rewardToken = rewardToken_;
    asset = asset_;
    _addReward(rewardToken_);
  }

  function addReward(address reward) external {
    _addReward(reward);
  }

  function _addReward(address reward) internal {
    if (_isReward[reward]) return;
    _isReward[reward] = true;
    _rewardsList.push(reward);
  }

  function setClaimer(address user, address claimer) external {
    _claimers[user] = claimer;
  }

  function getClaimer(address user) external view returns (address) {
    return _claimers[user];
  }

  function setTransferStrategy(address reward, address strategy) external {
    _transferStrategies[reward] = strategy;
  }

  function setAssetIndex(uint256 index) external {
    _assetIndexes[rewardToken] = index;
  }

  function setAssetIndexForReward(address reward, uint256 index) external {
    require(_isReward[reward], 'REWARD');
    _assetIndexes[reward] = index;
  }

  function removeReward(address reward) external {
    _isReward[reward] = false;
    _transferStrategies[reward] = address(0);
  }

  function getRewardsByAsset(address asset_) external view returns (address[] memory) {
    require(asset_ == asset, 'ASSET');
    address[] memory rewards = new address[](_rewardsList.length);
    for (uint256 i = 0; i < _rewardsList.length; i++) {
      rewards[i] = _rewardsList[i];
    }
    return rewards;
  }

  function getAssetIndex(address asset_, address reward) external view returns (uint256, uint256) {
    require(asset_ == asset, 'ASSET');
    require(_isReward[reward], 'REWARD');
    return (0, _assetIndexes[reward]);
  }

  function getUserRewards(address[] calldata, address, address) external pure returns (uint256) {
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
    if (to == address(0)) revert InvalidToAddress();
    require(assets.length == 1 && assets[0] == asset, 'ASSET');
    require(_isReward[reward], 'REWARD');
    address strategy = _transferStrategies[reward];
    require(strategy != address(0), 'STRATEGY');

    uint256 claimAmount = amount;
    uint256 available = E2EToken(reward).balanceOf(address(this));
    if (amount == type(uint256).max) {
      claimAmount = available;
    } else if (claimAmount > available) {
      claimAmount = available;
    }

    bool ok = IE2ETransferStrategy(strategy).performTransfer(
      to,
      reward,
      claimAmount,
      lockTime,
      tokenId
    );
    require(ok, 'TRANSFER');
    return claimAmount;
  }
}

contract E2ERewardsControllerV4 {
  address public immutable rewardToken;
  address public immutable asset;
  mapping(address => address) internal _claimers;
  uint256 public assetIndex;

  constructor(address rewardToken_, address asset_) {
    rewardToken = rewardToken_;
    asset = asset_;
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

  function getUserRewards(address[] calldata, address, address) external pure returns (uint256) {
    return 0;
  }

  function claimRewards(
    address[] calldata assets,
    uint256 amount,
    address to,
    address reward
  ) external returns (uint256) {
    require(to != address(0), 'TO');
    require(assets.length == 1 && assets[0] == asset, 'ASSET');
    require(reward == rewardToken, 'REWARD');

    uint256 available = E2EToken(rewardToken).balanceOf(address(this));
    uint256 claimAmount = amount;
    if (amount == type(uint256).max) {
      claimAmount = available;
    } else if (claimAmount > available) {
      claimAmount = available;
    }

    if (claimAmount == 0) {
      return 0;
    }

    E2EToken(rewardToken).transfer(to, claimAmount);
    return claimAmount;
  }
}

contract StaticATokenLME2ETest is Test {
  uint256 internal constant PENALTY_BPS = 5_000;
  uint256 internal constant REWARD_INDEX = 1e18;
  uint256 internal constant USER_BALANCE = 100e18;

  address internal constant USER = address(0x1);
  address internal constant USER2 = address(0x2);
  address internal constant CLAIMER = address(0x3);
  address internal constant TREASURY = address(0x4);

  E2EPool internal pool;
  E2EToken internal underlying;
  E2EAToken internal aToken;
  E2EToken internal dust;
  E2EDustLock internal dustLock;
  E2EDustLockTransferStrategy internal strategy;
  E2ERewardsController internal controller;
  StaticATokenLM internal staticATokenLM;

  function setUp() public {
    pool = new E2EPool();
    underlying = new E2EToken('Underlying', 'UND', 18);
    aToken = new E2EAToken(address(pool), address(underlying));
    dust = new E2EToken('Dust', 'DUST', 18);
    dustLock = new E2EDustLock(address(dust), TREASURY, PENALTY_BPS);
    controller = new E2ERewardsController(address(dust), address(aToken));
    strategy = new E2EDustLockTransferStrategy(address(controller), address(dust), address(dustLock));
    controller.setTransferStrategy(address(dust), address(strategy));

    vm.prank(address(controller));
    dust.approve(address(strategy), type(uint256).max);

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

  function _rewardsArray() internal view returns (address[] memory rewards) {
    rewards = new address[](1);
    rewards[0] = address(dust);
  }

  function test_e2e_liquidClaim_penalty() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
    assertEq(dust.balanceOf(address(staticATokenLM)), 0);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_e2e_lockClaim_newLock() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, _rewardsArray(), 7 days, 0);

    uint256 tokenId = dustLock.nextId() - 1;
    assertEq(dustLock.ownerOf(tokenId), USER);
    assertEq(dustLock.lockAmount(tokenId), userReward);
    assertEq(dust.balanceOf(address(dustLock)), userReward);
    assertEq(dust.balanceOf(address(staticATokenLM)), 0);
  }

  function test_e2e_lockClaim_addToExistingToken() public {
    dust.mint(address(dustLock), 10e18);
    uint256 tokenId = dustLock.createLockFor(10e18, 7 days, USER);

    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, _rewardsArray(), 0, tokenId);

    assertEq(dustLock.lockAmount(tokenId), 10e18 + userReward);
    assertEq(dust.balanceOf(address(dustLock)), 10e18 + userReward);
  }

  function test_e2e_lockClaim_permanent() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, _rewardsArray(), type(uint256).max, 0);

    uint256 tokenId = dustLock.nextId() - 1;
    assertEq(dustLock.isPermanent(tokenId), true);
  }

  function test_e2e_claimOnBehalf_authorizedClaimer() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);
    controller.setClaimer(USER, CLAIMER);

    vm.prank(CLAIMER);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, USER, _rewardsArray(), 0, 0);

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
  }

  function test_e2e_claimOnBehalf_receiverDiffers_updatesUserAccounting() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);
    controller.setClaimer(USER, CLAIMER);

    address receiver = address(0x9);
    vm.prank(CLAIMER);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, receiver, _rewardsArray(), 0, 0);

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(receiver), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
    assertEq(staticATokenLM.getClaimableRewards(USER, address(dust)), 0);
  }

  function test_e2e_claimOnBehalf_unauthorizedReverts() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.expectRevert(abi.encodeWithSignature('Error(string)', StaticATokenErrors.INVALID_CLAIMER));
    vm.prank(USER2);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, USER, _rewardsArray(), 0, 0);
  }

  function test_e2e_partialClaim_keepsUnclaimed() public {
    uint256 userReward = _accrueRewards();
    uint256 partialAmount = userReward / 2;
    dust.mint(address(controller), partialAmount);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    uint256 penalty1 = (partialAmount * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), partialAmount - penalty1);
    assertEq(dust.balanceOf(TREASURY), penalty1);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), userReward - partialAmount);

    dust.mint(address(controller), userReward - partialAmount);
    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    uint256 penalty2 = ((userReward - partialAmount) * PENALTY_BPS) / 10_000;
    assertEq(
      dust.balanceOf(USER),
      (partialAmount - penalty1) + (userReward - partialAmount) - penalty2
    );
    assertEq(dust.balanceOf(TREASURY), penalty1 + penalty2);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), 0);
  }

  function test_e2e_claimOnBehalf_afterUserTransfersAll() public {
    controller.setClaimer(USER, CLAIMER);
    controller.setAssetIndex(REWARD_INDEX);

    vm.prank(USER);
    staticATokenLM.transfer(USER2, USER_BALANCE);

    uint256 claimable = staticATokenLM.getClaimableRewards(USER, address(dust));
    dust.mint(address(controller), claimable);

    vm.prank(CLAIMER);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, USER, _rewardsArray(), 0, 0);

    uint256 penalty = (claimable * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), claimable - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
    assertEq(staticATokenLM.getClaimableRewards(USER, address(dust)), 0);
  }

  function test_e2e_claimWithZeroBalance_stillReceivesUnclaimed() public {
    controller.setAssetIndex(REWARD_INDEX);
    vm.prank(USER);
    staticATokenLM.transfer(USER2, USER_BALANCE);

    uint256 claimable = staticATokenLM.getClaimableRewards(USER, address(dust));
    dust.mint(address(controller), claimable);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    uint256 penalty = (claimable * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), claimable - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
    assertEq(staticATokenLM.getClaimableRewards(USER, address(dust)), 0);
  }

  function test_e2e_claimRewards_receiverZero_reverts() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.expectRevert(E2ERewardsController.InvalidToAddress.selector);
    vm.prank(USER);
    staticATokenLM.claimRewards(address(0), _rewardsArray());
  }

  function test_e2e_claimRewards_unregisteredReward_reverts() public {
    E2EToken otherReward = new E2EToken('Other', 'OTR', 18);
    address[] memory rewards = new address[](1);
    rewards[0] = address(otherReward);

    vm.expectRevert(abi.encodeWithSignature('Error(string)', 'REWARD'));
    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);
  }

  function test_e2e_claimRewards_noRewards_noTransfer() public {
    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    assertEq(dust.balanceOf(USER), 0);
    assertEq(dust.balanceOf(TREASURY), 0);
  }

  function test_e2e_claimRewards_ignoresZeroRewardAddress() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    address[] memory rewards = new address[](2);
    rewards[0] = address(0);
    rewards[1] = address(dust);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
  }

  function test_e2e_claimRewards_duplicateRewards_noDoubleClaim() public {
    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    address[] memory rewards = new address[](2);
    rewards[0] = address(dust);
    rewards[1] = address(dust);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    uint256 penalty = (userReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), userReward - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
  }

  function test_e2e_multipleRewards_mixedStrategies() public {
    E2EToken otherReward = new E2EToken('Other', 'OTR', 18);
    E2ETransferStrategy otherStrategy = new E2ETransferStrategy(address(controller));

    controller.addReward(address(otherReward));
    controller.setTransferStrategy(address(otherReward), address(otherStrategy));
    vm.prank(address(controller));
    otherReward.approve(address(otherStrategy), type(uint256).max);
    staticATokenLM.refreshRewardTokens();

    controller.setAssetIndex(REWARD_INDEX);
    controller.setAssetIndexForReward(address(otherReward), 2e18);

    uint256 dustReward = staticATokenLM.getClaimableRewards(USER, address(dust));
    uint256 otherRewardAmount = staticATokenLM.getClaimableRewards(USER, address(otherReward));

    dust.mint(address(controller), dustReward);
    otherReward.mint(address(controller), otherRewardAmount);

    address[] memory rewards = new address[](2);
    rewards[0] = address(dust);
    rewards[1] = address(otherReward);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    uint256 dustPenalty = (dustReward * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), dustReward - dustPenalty);
    assertEq(dust.balanceOf(TREASURY), dustPenalty);
    assertEq(otherReward.balanceOf(USER), otherRewardAmount);
  }

  function test_e2e_multipleRewards_feeTransferStrategy_underpays() public {
    E2EToken otherReward = new E2EToken('Other', 'OTR', 18);
    E2EFeeTransferStrategy feeStrategy = new E2EFeeTransferStrategy(address(controller), 100);

    controller.addReward(address(otherReward));
    controller.setTransferStrategy(address(otherReward), address(feeStrategy));
    vm.prank(address(controller));
    otherReward.approve(address(feeStrategy), type(uint256).max);
    staticATokenLM.refreshRewardTokens();

    controller.setAssetIndexForReward(address(otherReward), REWARD_INDEX);
    uint256 otherRewardAmount = staticATokenLM.getClaimableRewards(USER, address(otherReward));
    otherReward.mint(address(controller), otherRewardAmount);

    address[] memory rewards = new address[](1);
    rewards[0] = address(otherReward);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    uint256 fee = (otherRewardAmount * 100) / 10_000;
    assertEq(otherReward.balanceOf(USER), otherRewardAmount - fee);
    assertEq(staticATokenLM.getClaimableRewards(USER, address(otherReward)), 0);
  }

  function test_e2e_multipleRewards_missingStrategy_revertsAndNoTransfers() public {
    E2EToken otherReward = new E2EToken('Other', 'OTR', 18);

    controller.addReward(address(otherReward));
    staticATokenLM.refreshRewardTokens();

    controller.setAssetIndex(REWARD_INDEX);
    controller.setAssetIndexForReward(address(otherReward), REWARD_INDEX);

    uint256 dustReward = staticATokenLM.getClaimableRewards(USER, address(dust));
    uint256 otherRewardAmount = staticATokenLM.getClaimableRewards(USER, address(otherReward));

    dust.mint(address(controller), dustReward);
    otherReward.mint(address(controller), otherRewardAmount);

    address[] memory rewards = new address[](2);
    rewards[0] = address(dust);
    rewards[1] = address(otherReward);

    vm.expectRevert(abi.encodeWithSignature('Error(string)', 'STRATEGY'));
    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    assertEq(dust.balanceOf(USER), 0);
    assertEq(otherReward.balanceOf(USER), 0);
  }

  function test_e2e_rewardRemoved_revertsAndNoTransfers() public {
    E2EToken otherReward = new E2EToken('Other', 'OTR', 18);
    E2ETransferStrategy otherStrategy = new E2ETransferStrategy(address(controller));

    controller.addReward(address(otherReward));
    controller.setTransferStrategy(address(otherReward), address(otherStrategy));
    vm.prank(address(controller));
    otherReward.approve(address(otherStrategy), type(uint256).max);
    staticATokenLM.refreshRewardTokens();

    controller.removeReward(address(otherReward));

    otherReward.mint(address(controller), 10e18);
    address[] memory rewards = new address[](1);
    rewards[0] = address(otherReward);

    vm.expectRevert(abi.encodeWithSignature('Error(string)', 'REWARD'));
    vm.prank(USER);
    staticATokenLM.claimRewards(USER, rewards);

    assertEq(otherReward.balanceOf(USER), 0);
  }

  function test_e2e_collectAndUpdateRewards_zeroReward_returnsZero() public {
    uint256 claimed = staticATokenLM.collectAndUpdateRewards(address(0));
    assertEq(claimed, 0);
  }

  function test_e2e_lockClaim_invalidTokenId_reverts() public {
    uint256 tokenId = dustLock.createLockFor(10e18, 7 days, USER);

    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.expectRevert(bytes('NOT_OWNER'));
    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER2, _rewardsArray(), 0, tokenId);

    assertEq(staticATokenLM.getClaimableRewards(USER, address(dust)), userReward);
  }

  function test_e2e_lockClaim_partialFunding_keepsUnclaimed() public {
    uint256 userReward = _accrueRewards();
    uint256 partialAmount = userReward / 2;
    dust.mint(address(controller), partialAmount);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, _rewardsArray(), 7 days, 0);

    uint256 tokenId = dustLock.nextId() - 1;
    assertEq(dustLock.lockAmount(tokenId), partialAmount);
    assertEq(staticATokenLM.getUnclaimedRewards(USER, address(dust)), userReward - partialAmount);
  }

  function test_e2e_collectAndUpdateRewards_toWrapper() public {
    uint256 amount = 80e18;
    dust.mint(address(controller), amount);

    uint256 claimed = staticATokenLM.collectAndUpdateRewards(address(dust));
    uint256 penalty = (amount * PENALTY_BPS) / 10_000;

    assertEq(claimed, amount - penalty);
    assertEq(dust.balanceOf(address(staticATokenLM)), amount - penalty);
    assertEq(dust.balanceOf(TREASURY), penalty);
  }

  function test_e2e_claims_across_epochs() public {
    uint256 reward1 = _accrueRewards();
    dust.mint(address(controller), reward1);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, _rewardsArray(), 7 days, 0);

    controller.setAssetIndex(2e18);
    uint256 reward2 = staticATokenLM.getClaimableRewards(USER, address(dust));
    dust.mint(address(controller), reward2);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    uint256 penalty = (reward2 * PENALTY_BPS) / 10_000;
    assertEq(dust.balanceOf(USER), reward2 - penalty);
  }

  function test_e2e_rewardIndexDecreases_reverts() public {
    uint256 reward1 = _accrueRewards();
    dust.mint(address(controller), reward1);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    controller.setAssetIndex(REWARD_INDEX / 2);
    vm.expectRevert(stdError.arithmeticError);
    staticATokenLM.getClaimableRewards(USER, address(dust));
  }

  function test_e2e_lockClaim_tokenIdOverridesLockTime() public {
    dust.mint(address(dustLock), 10e18);
    uint256 tokenId = dustLock.createLockFor(10e18, 7 days, USER);
    uint256 nextIdBefore = dustLock.nextId();

    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.prank(USER);
    staticATokenLM.claimRewardsWithLock(USER, _rewardsArray(), 30 days, tokenId);

    assertEq(dustLock.lockAmount(tokenId), 10e18 + userReward);
    assertEq(dustLock.nextId(), nextIdBefore);
  }

  function test_e2e_claimerReset_revokesAccess() public {
    controller.setClaimer(USER, CLAIMER);
    controller.setClaimer(USER, address(0));

    uint256 userReward = _accrueRewards();
    dust.mint(address(controller), userReward);

    vm.expectRevert(abi.encodeWithSignature('Error(string)', StaticATokenErrors.INVALID_CLAIMER));
    vm.prank(CLAIMER);
    staticATokenLM.claimRewardsOnBehalfWithLock(USER, USER, _rewardsArray(), 0, 0);
  }

  function test_e2e_transfer_settlesRewardsForSender() public {
    controller.setAssetIndex(1e18);

    vm.prank(USER);
    staticATokenLM.transfer(USER2, USER_BALANCE / 2);

    controller.setAssetIndex(2e18);

    uint256 userClaimable = staticATokenLM.getClaimableRewards(USER, address(dust));
    uint256 user2Claimable = staticATokenLM.getClaimableRewards(USER2, address(dust));

    assertEq(userClaimable, USER_BALANCE + (USER_BALANCE / 2));
    assertEq(user2Claimable, USER_BALANCE / 2);

    dust.mint(address(controller), userClaimable + user2Claimable);

    vm.prank(USER);
    staticATokenLM.claimRewards(USER, _rewardsArray());

    vm.prank(USER2);
    staticATokenLM.claimRewards(USER2, _rewardsArray());

    uint256 penaltyUser = (userClaimable * PENALTY_BPS) / 10_000;
    uint256 penaltyUser2 = (user2Claimable * PENALTY_BPS) / 10_000;

    assertEq(dust.balanceOf(USER), userClaimable - penaltyUser);
    assertEq(dust.balanceOf(USER2), user2Claimable - penaltyUser2);
    assertEq(dust.balanceOf(TREASURY), penaltyUser + penaltyUser2);
  }

  function test_e2e_reentrantStrategy_noDoublePay() public {
    E2EPool pool2 = new E2EPool();
    E2EToken underlying2 = new E2EToken('Underlying2', 'UND2', 18);
    E2EAToken aToken2 = new E2EAToken(address(pool2), address(underlying2));
    E2EToken reward2 = new E2EToken('Reward2', 'RWD2', 18);
    E2ERewardsController controller2 = new E2ERewardsController(address(reward2), address(aToken2));

    StaticATokenLM impl = new StaticATokenLM(
      IPool(address(pool2)),
      IRewardsController(address(controller2))
    );
    bytes memory initData = abi.encodeWithSelector(
      StaticATokenLM.initialize.selector,
      address(aToken2),
      'Static aToken',
      'stata'
    );
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(impl),
      address(0xBEEF),
      initData
    );
    StaticATokenLM local = StaticATokenLM(address(proxy));

    E2EReentrantStrategy reentrantStrategy = new E2EReentrantStrategy(
      address(controller2),
      local,
      USER,
      address(reward2)
    );
    controller2.setTransferStrategy(address(reward2), address(reentrantStrategy));
    controller2.setClaimer(USER, address(reentrantStrategy));

    vm.prank(address(controller2));
    reward2.approve(address(reentrantStrategy), type(uint256).max);

    aToken2.mint(USER, USER_BALANCE);
    vm.startPrank(USER);
    aToken2.approve(address(local), USER_BALANCE);
    local.deposit(USER_BALANCE, USER, 0, false);
    vm.stopPrank();

    controller2.setAssetIndex(REWARD_INDEX);
    uint256 claimable = local.getClaimableRewards(USER, address(reward2));
    reward2.mint(address(controller2), claimable);

    address[] memory rewards = new address[](1);
    rewards[0] = address(reward2);

    vm.prank(USER);
    local.claimRewards(USER, rewards);

    assertEq(reward2.balanceOf(USER), claimable);
    assertEq(local.getClaimableRewards(USER, address(reward2)), 0);
    assertTrue(reentrantStrategy.entered());
    assertTrue(reentrantStrategy.transferred());
  }

  function test_e2e_fallbackController_4argClaim() public {
    E2EPool pool2 = new E2EPool();
    E2EToken underlying2 = new E2EToken('Underlying2', 'UND2', 18);
    E2EAToken aToken2 = new E2EAToken(address(pool2), address(underlying2));
    E2EToken reward2 = new E2EToken('Reward2', 'RWD2', 18);
    E2ERewardsControllerV4 controllerV4 = new E2ERewardsControllerV4(
      address(reward2),
      address(aToken2)
    );

    StaticATokenLM impl = new StaticATokenLM(
      IPool(address(pool2)),
      IRewardsController(address(controllerV4))
    );
    bytes memory initData = abi.encodeWithSelector(
      StaticATokenLM.initialize.selector,
      address(aToken2),
      'Static aToken',
      'stata'
    );
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(impl),
      address(0xBEEF),
      initData
    );
    StaticATokenLM local = StaticATokenLM(address(proxy));

    aToken2.mint(USER, USER_BALANCE);
    vm.startPrank(USER);
    aToken2.approve(address(local), USER_BALANCE);
    local.deposit(USER_BALANCE, USER, 0, false);
    vm.stopPrank();

    controllerV4.setAssetIndex(REWARD_INDEX);
    uint256 claimable = local.getClaimableRewards(USER, address(reward2));
    reward2.mint(address(controllerV4), claimable);

    address[] memory rewards = new address[](1);
    rewards[0] = address(reward2);

    vm.prank(USER);
    local.claimRewards(USER, rewards);

    assertEq(reward2.balanceOf(USER), claimable);
  }
}
