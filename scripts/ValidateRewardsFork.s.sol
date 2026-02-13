// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import "forge-std/StdStorage.sol";
import "forge-std/console2.sol";

import {StaticATokenLM} from "../src/StaticATokenLM.sol";
import {NeverlandMonadMainnet} from "../src/NeverlandAddressBook.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {IERC20Metadata} from "solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

interface IDustRewardsControllerView {
    function getTransferStrategy(address reward) external view returns (address);
    function getClaimer(address user) external view returns (address);
}

interface IRewardsControllerEmissionManager {
    function getEmissionManager() external view returns (address);
}

interface IDustLockTransferStrategyView {
    function DUST_LOCK() external view returns (address);
    function DUST_VAULT() external view returns (address);
    function DUST() external view returns (address);
}

interface IDustLockView {
    struct LockedBalance {
        int256 amount;
        uint256 effectiveStart;
        uint256 end;
        bool isPermanent;
    }

    function earlyWithdrawPenalty() external view returns (uint256);
    function earlyWithdrawTreasury() external view returns (address);
    function minLockAmount() external view returns (uint256);
    function tokenId() external view returns (uint256);
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function createLockFor(uint256 amount, uint256 lockTime, address to) external returns (uint256);
}

contract MockVault {}

contract MockDistributor {}

contract ValidateRewardsFork is Script {
    using stdStorage for StdStorage;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant LOCK_DURATION = 8 weeks;

    enum ScenarioStatus {
        Unknown,
        Pass,
        Fail,
        Skip
    }

    ScenarioStatus internal statusA;
    ScenarioStatus internal statusB;
    ScenarioStatus internal statusC;
    ScenarioStatus internal statusD;
    ScenarioStatus internal statusE;
    ScenarioStatus internal statusF;
    ScenarioStatus internal statusG;
    ScenarioStatus internal statusH;
    ScenarioStatus internal statusI;

    address internal vault;
    address internal distributor;

    StaticATokenLM internal wrapper;
    IRewardsController internal controller;
    address internal wrapperAddr;
    address internal aToken;
    address internal underlying;
    bool internal depositToAave;
    uint16 internal referralCode;

    address internal dust;
    address internal strategy;
    address internal dustLock;
    address internal dustVault;
    uint256 internal penaltyBps;
    address internal treasury;
    uint256 internal minLockAmount;

    address internal user;
    address internal user2;
    address internal claimer;
    uint256 internal userPk;
    address internal claimerSetter;

    uint256 internal depositAmount;
    uint256 internal warpSeconds;
    uint256 internal existingTokenId;
    uint256 internal seedLockAmount;
    uint256 internal lockTopupAmount;
    uint256 internal lockWarpSeconds;
    uint256 internal lockMaxRounds;

    function run() external {
        _initContext();
        _seedUsersAndDeposit();

        _scenarioLiquidClaim();
        _scenarioLockClaimNew();
        _scenarioLockClaimExisting();
        _scenarioClaimToSelf();
        _scenarioAuthorizedClaimer();
        _scenarioVaultClaimer();
        _scenarioPartialClaimFeasibility();
        _scenarioZeroBalanceClaim();
        _scenarioCollectToWrapper();

        _printSummary();

        console2.log("\nValidation complete");
    }

    function _initContext() internal {
        wrapperAddr = vm.envOr("STATIC_ATOKEN", address(0));
        if (wrapperAddr == address(0)) {
            (wrapperAddr, aToken) = _deployWrapper();
            console2.log("Deployed StaticATokenLM", wrapperAddr);
        }

        wrapper = StaticATokenLM(wrapperAddr);
        if (aToken == address(0)) {
            aToken = address(wrapper.aToken());
        }
        underlying = _resolveUnderlyingFromAddressBook(aToken);
        require(underlying == wrapper.asset(), "UNDERLYING_MISMATCH");
        controller = wrapper.INCENTIVES_CONTROLLER();

        console2.log("============================");
        console2.log("StaticATokenLM Fork Validation");
        console2.log("============================");
        console2.log("chainId", block.chainid);
        console2.log("block", block.number);
        console2.log("wrapper", wrapperAddr);
        console2.log("aToken", aToken);
        console2.log("underlying", underlying);
        console2.log("controller", address(controller));
        try wrapper.name() returns (string memory wrapperName) {
            console2.log("wrapperName", wrapperName);
        } catch {
            console2.log("wrapperName", "UNKNOWN");
        }
        try wrapper.symbol() returns (string memory wrapperSymbol) {
            console2.log("wrapperSymbol", wrapperSymbol);
        } catch {
            console2.log("wrapperSymbol", "UNKNOWN");
        }
        try wrapper.decimals() returns (uint8 wrapperDecimals) {
            console2.log("wrapperDecimals", wrapperDecimals);
        } catch {
            console2.log("wrapperDecimals", uint256(0));
        }

        console2.log("\nRefreshing reward tokens");
        try wrapper.refreshRewardTokens() {
            console2.log("refreshRewardTokens ok");
        } catch {
            console2.log("WARN: refreshRewardTokens reverted");
        }

        address[] memory rewards = controller.getRewardsByAsset(aToken);
        console2.log("rewardTokens.length", rewards.length);
        for (uint256 i = 0; i < rewards.length; i++) {
            console2.log("reward", i, rewards[i]);
        }

        dust = vm.envOr("DUST", rewards.length > 0 ? rewards[0] : address(0));
        require(dust != address(0), "DUST address not found");

        _loadDustConfig();

        address[] memory wrapperRewards = wrapper.rewardTokens();
        console2.log("wrapper.rewardTokens.length", wrapperRewards.length);
        for (uint256 i = 0; i < wrapperRewards.length; i++) {
            console2.log("wrapperReward", i, wrapperRewards[i]);
        }
        console2.log("dustRegistered", wrapper.isRegisteredRewardToken(dust));
        _assertConfig();

        userPk = vm.envOr("USER_PK", uint256(0xA11CE));
        user = vm.addr(userPk);
        user2 = vm.addr(userPk + 1);
        claimer = vm.addr(userPk + 2);
        claimerSetter = vm.envOr("CLAIMER_SETTER", address(0));
        if (claimerSetter == address(0)) {
            (bool ok, bytes memory data) = address(controller).call(abi.encodeWithSignature("owner()"));
            if (ok && data.length == 32) {
                claimerSetter = abi.decode(data, (address));
                console2.log("claimerSetter(owner)", claimerSetter);
            }
        }

        uint8 assetDecimals = IERC20Metadata(underlying).decimals();
        uint256 unit = 10 ** assetDecimals;
        depositAmount = vm.envOr("DEPOSIT_AMOUNT", 1_000 * unit);
        warpSeconds = vm.envOr("WARP_SECONDS", uint256(1 days));
        existingTokenId = vm.envOr("EXISTING_TOKEN_ID", uint256(0));
        seedLockAmount = vm.envOr("SEED_LOCK_AMOUNT", uint256(0));
        depositToAave = vm.envOr("DEPOSIT_TO_AAVE", true);
        referralCode = uint16(vm.envOr("REFERRAL_CODE", uint256(0)));
        lockTopupAmount = vm.envOr("LOCK_TOPUP_AMOUNT", uint256(0));
        lockWarpSeconds = vm.envOr("LOCK_WARP_SECONDS", uint256(0));
        lockMaxRounds = vm.envOr("LOCK_MAX_ROUNDS", uint256(0));

        console2.log("user", user);
        console2.log("claimer", claimer);
        console2.log("depositAmount", depositAmount);
        console2.log("warpSeconds", warpSeconds);
        console2.log("depositToAave", depositToAave);
        console2.log("referralCode", referralCode);
        console2.log("lockTopupAmount(config)", lockTopupAmount);
        console2.log("lockWarpSeconds(config)", lockWarpSeconds);
        console2.log("lockMaxRounds(config)", lockMaxRounds);
    }

    function _loadDustConfig() internal {
        strategy = address(0);
        dustLock = address(0);
        dustVault = address(0);
        penaltyBps = 0;
        treasury = address(0);
        minLockAmount = 0;

        try IDustRewardsControllerView(address(controller)).getTransferStrategy(dust) returns (address strategyAddr) {
            strategy = strategyAddr;
        } catch {
            console2.log("WARN: controller.getTransferStrategy not available");
        }

        if (strategy != address(0)) {
            console2.log("strategy", strategy);
            try IDustLockTransferStrategyView(strategy).DUST_LOCK() returns (address lockAddr) {
                dustLock = lockAddr;
            } catch {}
            try IDustLockTransferStrategyView(strategy).DUST_VAULT() returns (address vaultAddr) {
                dustVault = vaultAddr;
            } catch {}

            if (dustLock != address(0)) {
                penaltyBps = IDustLockView(dustLock).earlyWithdrawPenalty();
                treasury = IDustLockView(dustLock).earlyWithdrawTreasury();
                minLockAmount = IDustLockView(dustLock).minLockAmount();
            }
        }

        console2.log("DUST", dust);
        console2.log("strategy", strategy);
        console2.log("dustLock", dustLock);
        console2.log("dustVault", dustVault);
        console2.log("penaltyBps", penaltyBps);
        console2.log("treasury", treasury);
        console2.log("minLockAmount", minLockAmount);

        if (dustVault != address(0)) {
            uint256 vaultBal = IERC20(dust).balanceOf(dustVault);
            uint256 vaultAllowance = IERC20(dust).allowance(dustVault, strategy);
            console2.log("dustVault balance", vaultBal);
            console2.log("dustVault allowance to strategy", vaultAllowance);
        }
    }

    function _assertConfig() internal view {
        console2.log("\nAsserting config");
        address expectedController = vm.envOr("EXPECTED_CONTROLLER", NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER);
        require(address(controller) == expectedController, "CONTROLLER_MISMATCH");
        require(wrapper.isRegisteredRewardToken(dust), "DUST_NOT_REGISTERED");
        require(strategy != address(0), "STRATEGY_NOT_SET");
        require(dustLock != address(0), "DUST_LOCK_NOT_SET");
        require(dustVault != address(0), "DUST_VAULT_NOT_SET");
        require(treasury != address(0), "TREASURY_NOT_SET");
        require(penaltyBps > 0, "PENALTY_BPS_ZERO");
        require(minLockAmount > 0, "MIN_LOCK_AMOUNT_ZERO");

        address expectedDust = vm.envOr("EXPECTED_DUST", address(0));
        if (expectedDust != address(0)) {
            require(dust == expectedDust, "DUST_MISMATCH");
        }

        address expectedStrategy = vm.envOr("EXPECTED_STRATEGY", address(0));
        if (expectedStrategy != address(0)) {
            require(strategy == expectedStrategy, "STRATEGY_MISMATCH");
        }

        address expectedTreasury = vm.envOr("EXPECTED_TREASURY", address(0));
        if (expectedTreasury != address(0)) {
            require(treasury == expectedTreasury, "TREASURY_MISMATCH");
        }

        uint256 expectedPenalty = vm.envOr("EXPECTED_PENALTY_BPS", uint256(0));
        if (expectedPenalty != 0) {
            require(penaltyBps == expectedPenalty, "PENALTY_BPS_MISMATCH");
        }

        uint256 expectedMinLock = vm.envOr("EXPECTED_MIN_LOCK_AMOUNT", uint256(0));
        if (expectedMinLock != 0) {
            require(minLockAmount == expectedMinLock, "MIN_LOCK_MISMATCH");
        }

        address expectedDustLock = vm.envOr("EXPECTED_DUST_LOCK", address(0));
        if (expectedDustLock != address(0)) {
            require(dustLock == expectedDustLock, "DUST_LOCK_MISMATCH");
        }

        address expectedDustVault = vm.envOr("EXPECTED_DUST_VAULT", address(0));
        if (expectedDustVault != address(0)) {
            require(dustVault == expectedDustVault, "DUST_VAULT_MISMATCH");
        }

        string memory expectedName = string(abi.encodePacked("Wrapped Neverland ", IERC20Metadata(underlying).symbol()));
        string memory expectedSymbol = string(abi.encodePacked("w", IERC20Metadata(aToken).symbol()));
        require(keccak256(bytes(wrapper.name())) == keccak256(bytes(expectedName)), "WRAPPER_NAME_MISMATCH");
        require(keccak256(bytes(wrapper.symbol())) == keccak256(bytes(expectedSymbol)), "WRAPPER_SYMBOL_MISMATCH");
        require(wrapper.decimals() == IERC20Metadata(underlying).decimals(), "WRAPPER_DECIMALS_MISMATCH");
    }

    function _seedUsersAndDeposit() internal {
        vm.deal(user, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(claimer, 10 ether);

        if (depositToAave) {
            deal(underlying, user, depositAmount);
            vm.startPrank(user);
            IERC20(underlying).approve(wrapperAddr, depositAmount);
            wrapper.deposit(depositAmount, user, referralCode, true);
            vm.stopPrank();
        } else {
            deal(aToken, user, depositAmount);
            vm.startPrank(user);
            IERC20(aToken).approve(wrapperAddr, depositAmount);
            wrapper.deposit(depositAmount, user, referralCode, false);
            vm.stopPrank();
        }

        _advanceTime(warpSeconds);
    }

    function _scenarioLiquidClaim() internal {
        console2.log("\nScenario A: Liquid claim (lockTime=0, tokenId=0)");
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "liquidClaim");
        if (!okClaimable) {
            statusA = ScenarioStatus.Fail;
            return;
        }
        console2.log("claimable", claimable);
        if (claimable == 0) {
            console2.log("SKIP: no rewards accrued");
            statusA = ScenarioStatus.Skip;
            return;
        }

        uint256 userBefore = IERC20(dust).balanceOf(user);
        uint256 treasuryBefore = treasury == address(0) ? 0 : IERC20(dust).balanceOf(treasury);

        bool ok = _callClaimRewards(user, user, "claimRewards");
        if (!ok) {
            statusA = ScenarioStatus.Fail;
            return;
        }

        uint256 userDelta = IERC20(dust).balanceOf(user) - userBefore;
        uint256 treasuryDelta = treasury == address(0) ? 0 : IERC20(dust).balanceOf(treasury) - treasuryBefore;

        console2.log("userReceived", userDelta);
        console2.log("treasuryReceived", treasuryDelta);
        if (penaltyBps > 0) {
            uint256 expectedPenalty = (claimable * penaltyBps) / BPS;
            console2.log("expectedPenalty", expectedPenalty);
        }
        console2.log("remainingClaimable", wrapper.getClaimableRewards(user, dust));
        statusA = ScenarioStatus.Pass;
    }

    function _scenarioLockClaimNew() internal {
        _advanceTime(warpSeconds);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "lockClaim(new)");
        console2.log("\nScenario B: Lock claim (new veNFT)");
        if (!okClaimable) {
            statusB = ScenarioStatus.Fail;
            return;
        }
        console2.log("claimable", claimable);
        if (claimable == 0 || dustLock == address(0)) {
            console2.log("SKIP: no rewards or dustLock unavailable");
            statusB = ScenarioStatus.Skip;
            return;
        }
        if (minLockAmount > 0 && claimable < minLockAmount) {
            claimable = _reachMinLock(claimable);
            if (claimable < minLockAmount) {
                console2.log("SKIP: claimable below minLockAmount");
                statusB = ScenarioStatus.Skip;
                return;
            }
        }

        uint256 tokenIdBefore = IDustLockView(dustLock).tokenId();
        bool ok = _callClaimRewardsWithLock(user, user, LOCK_DURATION, 0, "claimRewardsWithLock(new)");
        if (!ok) {
            statusB = ScenarioStatus.Fail;
            return;
        }

        uint256 tokenIdAfter = IDustLockView(dustLock).tokenId();
        console2.log("tokenIdBefore", tokenIdBefore);
        console2.log("tokenIdAfter", tokenIdAfter);
        if (tokenIdAfter > tokenIdBefore) {
            existingTokenId = tokenIdAfter;
            console2.log("existingTokenId", existingTokenId);
            IDustLockView.LockedBalance memory lockInfo = IDustLockView(dustLock).locked(tokenIdAfter);
            console2.log("lockedAmount", uint256(lockInfo.amount));
        }
        console2.log("remainingClaimable", wrapper.getClaimableRewards(user, dust));
        statusB = ScenarioStatus.Pass;
    }

    function _scenarioLockClaimExisting() internal {
        if (existingTokenId == 0 && dustLock != address(0)) {
            if (seedLockAmount > 0) {
                deal(dust, user, seedLockAmount);
                vm.startPrank(user);
                IERC20(dust).approve(dustLock, seedLockAmount);
                try IDustLockView(dustLock).createLockFor(seedLockAmount, LOCK_DURATION, user) returns (
                    uint256 createdId
                ) {
                    existingTokenId = createdId;
                } catch {
                    console2.log("WARN: failed to create lock for user");
                }
                vm.stopPrank();
            }
        }

        console2.log("\nScenario C: Add to existing veNFT");
        if (existingTokenId == 0 || dustLock == address(0)) {
            console2.log("SKIP: no existing tokenId");
            statusC = ScenarioStatus.Skip;
            return;
        }

        _advanceTime(warpSeconds);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "lockClaim(existing)");
        if (!okClaimable) {
            statusC = ScenarioStatus.Fail;
            return;
        }
        console2.log("claimable", claimable);
        if (claimable == 0) {
            console2.log("SKIP: no rewards accrued");
            statusC = ScenarioStatus.Skip;
            return;
        }
        if (minLockAmount > 0 && claimable < minLockAmount) {
            claimable = _reachMinLock(claimable);
            if (claimable < minLockAmount) {
                console2.log("SKIP: claimable below minLockAmount");
                statusC = ScenarioStatus.Skip;
                return;
            }
        }

        IDustLockView.LockedBalance memory beforeLock = IDustLockView(dustLock).locked(existingTokenId);
        bool ok = _callClaimRewardsWithLock(user, user, 0, existingTokenId, "claimRewardsWithLock(existing)");
        if (!ok) {
            statusC = ScenarioStatus.Fail;
            return;
        }

        IDustLockView.LockedBalance memory afterLock = IDustLockView(dustLock).locked(existingTokenId);
        console2.log("lockedBefore", uint256(beforeLock.amount));
        console2.log("lockedAfter", uint256(afterLock.amount));
        console2.log("remainingClaimable", wrapper.getClaimableRewards(user, dust));
        statusC = ScenarioStatus.Pass;
    }

    function _scenarioClaimToSelf() internal {
        console2.log("\nScenario H: Claim to self");
        _advanceTime(warpSeconds);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "claimToSelf");
        if (!okClaimable) {
            statusH = ScenarioStatus.Fail;
            return;
        }
        console2.log("claimable", claimable);
        if (claimable == 0) {
            console2.log("SKIP: no rewards accrued");
            statusH = ScenarioStatus.Skip;
            return;
        }

        uint256 userBefore = IERC20(dust).balanceOf(user);
        vm.prank(user);
        try wrapper.claimRewardsToSelf(_singleReward(dust)) {}
        catch (bytes memory reason) {
            _logRevert("claimRewardsToSelf", reason);
            statusH = ScenarioStatus.Fail;
            return;
        }
        uint256 userDelta = IERC20(dust).balanceOf(user) - userBefore;
        console2.log("userReceived", userDelta);
        console2.log("remainingClaimable", wrapper.getClaimableRewards(user, dust));
        statusH = ScenarioStatus.Pass;
    }

    function _scenarioAuthorizedClaimer() internal {
        console2.log("\nScenario D: Authorized claimer claim on behalf");
        try IDustRewardsControllerView(address(controller)).getClaimer(user) returns (address current) {
            console2.log("currentClaimer", current);
        } catch {}

        bool setOk = false;
        vm.prank(user);
        (bool okSelf, bytes memory reasonSelf) =
            address(controller).call(abi.encodeWithSignature("setClaimer(address,address)", user, claimer));
        if (!okSelf) {
            _logRevert("setClaimer(self)", reasonSelf);
            if (claimerSetter != address(0)) {
                vm.prank(claimerSetter);
                (bool okAdmin, bytes memory reasonAdmin) =
                    address(controller).call(abi.encodeWithSignature("setClaimer(address,address)", user, claimer));
                setOk = okAdmin;
                if (!okAdmin) {
                    _logRevert("setClaimer(admin)", reasonAdmin);
                }
            } else {
                console2.log("WARN: claimerSetter not resolved; skipping admin setClaimer");
            }
        } else {
            setOk = true;
        }
        console2.log("setClaimer", setOk);

        _advanceTime(warpSeconds);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "claimerClaimable");
        if (!okClaimable) {
            statusD = ScenarioStatus.Fail;
            return;
        }
        console2.log("claimable", claimable);
        if (claimable == 0) {
            console2.log("SKIP: no rewards accrued");
            statusD = ScenarioStatus.Skip;
            return;
        }
        if (!setOk) {
            statusD = ScenarioStatus.Fail;
            return;
        }

        uint256 userBefore = IERC20(dust).balanceOf(user);
        bool claimedOk = _callClaimRewardsOnBehalfWithLock(claimer, user, user, 0, 0, "claimRewardsOnBehalfWithLock");
        if (!claimedOk) {
            statusD = ScenarioStatus.Fail;
            return;
        }

        uint256 userDelta = IERC20(dust).balanceOf(user) - userBefore;
        console2.log("userReceived", userDelta);
        console2.log("remainingClaimable", wrapper.getClaimableRewards(user, dust));
        statusD = ScenarioStatus.Pass;
    }

    function _scenarioVaultClaimer() internal {
        console2.log("\nScenario I: Vault claimer (contract)");
        if (vault == address(0)) {
            vault = address(new MockVault());
            distributor = address(new MockDistributor());
        }

        uint256 userBalance = wrapper.balanceOf(user);
        if (userBalance == 0) {
            console2.log("SKIP: user balance zero");
            statusI = ScenarioStatus.Skip;
            return;
        }

        uint256 transferAmount = userBalance / 2;
        if (transferAmount == 0) {
            console2.log("SKIP: transfer amount zero");
            statusI = ScenarioStatus.Skip;
            return;
        }

        vm.startPrank(user);
        try wrapper.transfer(vault, transferAmount) {}
        catch (bytes memory reason) {
            _logRevert("transferToVault", reason);
            vm.stopPrank();
            statusI = ScenarioStatus.Fail;
            return;
        }
        vm.stopPrank();

        _advanceTime(warpSeconds);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(vault, dust, "vaultClaimable");
        if (!okClaimable) {
            statusI = ScenarioStatus.Fail;
            return;
        }
        console2.log("claimable", claimable);
        if (claimable == 0) {
            console2.log("SKIP: no rewards accrued");
            statusI = ScenarioStatus.Skip;
            return;
        }

        address emissionManager = address(0);
        try IRewardsControllerEmissionManager(address(controller)).getEmissionManager() returns (address manager) {
            emissionManager = manager;
        } catch {}
        if (emissionManager == address(0)) {
            console2.log("SKIP: emissionManager not available");
            statusI = ScenarioStatus.Skip;
            return;
        }

        vm.prank(emissionManager);
        (bool setOk, bytes memory setReason) =
            address(controller).call(abi.encodeWithSignature("setClaimer(address,address)", vault, distributor));
        if (!setOk) {
            _logRevert("setClaimer(vault)", setReason);
            statusI = ScenarioStatus.Fail;
            return;
        }

        uint256 before = IERC20(dust).balanceOf(distributor);
        bool claimOk = _callClaimRewardsOnBehalfWithLock(distributor, vault, distributor, 0, 0, "vaultClaim");
        if (!claimOk) {
            statusI = ScenarioStatus.Fail;
            return;
        }
        uint256 delta = IERC20(dust).balanceOf(distributor) - before;
        console2.log("distributorReceived", delta);
        statusI = ScenarioStatus.Pass;
    }

    function _scenarioPartialClaimFeasibility() internal {
        console2.log("\nScenario E: Partial claim feasibility");
        if (dustVault == address(0)) {
            console2.log("SKIP: dustVault unknown");
            statusE = ScenarioStatus.Skip;
            return;
        }

        uint256 vaultBal = IERC20(dust).balanceOf(dustVault);
        console2.log("dustVault balance", vaultBal);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "partialClaim");
        if (!okClaimable) {
            statusE = ScenarioStatus.Fail;
            return;
        }
        if (claimable > vaultBal) {
            console2.log("WARN: vault balance < claimable; liquid claim would revert");
        } else {
            console2.log("OK: vault balance >= claimable");
        }
        statusE = ScenarioStatus.Pass;
    }

    function _scenarioZeroBalanceClaim() internal {
        console2.log("\nScenario F: Zero balance claims accrued rewards");
        _advanceTime(warpSeconds);
        (bool okClaimable, uint256 claimable) = _getClaimableRewardsSafe(user, dust, "zeroBalance");
        if (!okClaimable) {
            statusF = ScenarioStatus.Fail;
            return;
        }
        if (claimable == 0) {
            console2.log("SKIP: no rewards accrued");
            statusF = ScenarioStatus.Skip;
            return;
        }

        uint256 userBalance = wrapper.balanceOf(user);
        console2.log("userStaticBalance", userBalance);
        if (userBalance == 0) {
            console2.log("SKIP: user balance already zero");
            statusF = ScenarioStatus.Skip;
            return;
        }

        vm.startPrank(user);
        try wrapper.transfer(user2, userBalance) {}
        catch (bytes memory transferReason) {
            _logRevert("transferToUser2", transferReason);
            vm.stopPrank();
            statusF = ScenarioStatus.Fail;
            return;
        }
        vm.stopPrank();

        uint256 userBefore = IERC20(dust).balanceOf(user);
        bool ok = _callClaimRewards(user, user, "claimRewards(zeroBalance)");
        if (!ok) {
            statusF = ScenarioStatus.Fail;
            return;
        }

        uint256 userDelta = IERC20(dust).balanceOf(user) - userBefore;
        console2.log("userReceived", userDelta);
        console2.log("remainingClaimable", wrapper.getClaimableRewards(user, dust));
        statusF = ScenarioStatus.Pass;
    }

    function _scenarioCollectToWrapper() internal {
        console2.log("\nScenario G: Collect rewards to wrapper");
        _advanceTime(warpSeconds);
        uint256 wrapperBefore = IERC20(dust).balanceOf(wrapperAddr);
        try wrapper.collectAndUpdateRewards(dust) returns (uint256 collected) {
            console2.log("collected", collected);
            console2.log("wrapperDelta", IERC20(dust).balanceOf(wrapperAddr) - wrapperBefore);
            console2.log("wrapperBalance", IERC20(dust).balanceOf(wrapperAddr));
            statusG = ScenarioStatus.Pass;
        } catch (bytes memory reason) {
            _logRevert("collectAndUpdateRewards", reason);
            statusG = ScenarioStatus.Fail;
        }
    }

    function _printSummary() internal view {
        console2.log("\nScenario Summary");
        console2.log("A Liquid", _statusLabel(statusA));
        console2.log("B Lock New", _statusLabel(statusB));
        console2.log("C Lock Existing", _statusLabel(statusC));
        console2.log("D Claimer", _statusLabel(statusD));
        console2.log("E Partial", _statusLabel(statusE));
        console2.log("F ZeroBalance", _statusLabel(statusF));
        console2.log("G Collect", _statusLabel(statusG));
        console2.log("H ClaimToSelf", _statusLabel(statusH));
        console2.log("I VaultClaimer", _statusLabel(statusI));
    }

    function _statusLabel(ScenarioStatus status) internal pure returns (string memory) {
        if (status == ScenarioStatus.Pass) return "PASS";
        if (status == ScenarioStatus.Fail) return "FAIL";
        if (status == ScenarioStatus.Skip) return "SKIP";
        return "UNKNOWN";
    }

    function _callClaimRewards(address caller, address receiver, string memory label) internal returns (bool) {
        vm.prank(caller);
        try wrapper.claimRewards(receiver, _singleReward(dust)) {}
        catch (bytes memory reason) {
            _logRevert(label, reason);
            return false;
        }
        return true;
    }

    function _callClaimRewardsWithLock(
        address caller,
        address receiver,
        uint256 lockTime,
        uint256 tokenId,
        string memory label
    ) internal returns (bool) {
        vm.prank(caller);
        try wrapper.claimRewardsWithLock(receiver, _singleReward(dust), lockTime, tokenId) {}
        catch (bytes memory reason) {
            _logRevert(label, reason);
            return false;
        }
        return true;
    }

    function _callClaimRewardsOnBehalfWithLock(
        address caller,
        address onBehalfOf,
        address receiver,
        uint256 lockTime,
        uint256 tokenId,
        string memory label
    ) internal returns (bool) {
        vm.prank(caller);
        try wrapper.claimRewardsOnBehalfWithLock(onBehalfOf, receiver, _singleReward(dust), lockTime, tokenId) {}
        catch (bytes memory reason) {
            _logRevert(label, reason);
            return false;
        }
        return true;
    }

    function _getClaimableRewardsSafe(address account, address reward, string memory label)
        internal
        view
        returns (bool ok, uint256 claimable)
    {
        try wrapper.getClaimableRewards(account, reward) returns (uint256 amount) {
            return (true, amount);
        } catch (bytes memory reason) {
            _logRevert(label, reason);
            return (false, 0);
        }
    }

    function _reachMinLock(uint256 claimable) internal returns (uint256) {
        if (minLockAmount == 0 || claimable >= minLockAmount) {
            return claimable;
        }
        console2.log("claimable below minLockAmount, attempting topup");

        uint256 maxRounds = lockMaxRounds == 0 ? 5 : lockMaxRounds;
        uint256 topup = lockTopupAmount == 0 ? depositAmount * 100 : lockTopupAmount;
        uint256 warp = lockWarpSeconds == 0 ? 7 days : lockWarpSeconds;

        console2.log("topupAmount(effective)", topup);
        console2.log("warpSeconds(effective)", warp);
        console2.log("lockMaxRounds(effective)", maxRounds);

        for (uint256 i = 0; i < maxRounds && claimable < minLockAmount; i++) {
            console2.log("topupRound", i + 1);
            if (topup > 0) {
                _topUpUser(topup);
                console2.log("topupAmount", topup);
            }
            if (warp > 0) {
                _advanceTime(warp);
                console2.log("warpSeconds", warp);
            }
            (bool ok, uint256 nextClaimable) = _getClaimableRewardsSafe(user, dust, "lockClaim(topup)");
            if (!ok) {
                return 0;
            }
            claimable = nextClaimable;
            console2.log("claimable", claimable);

            if (claimable < minLockAmount) {
                topup *= 2;
            }
        }

        if (claimable < minLockAmount) {
            console2.log("WARN: still below minLockAmount");
            console2.log("shortfall", minLockAmount - claimable);
        }

        return claimable;
    }

    function _topUpUser(uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        if (depositToAave) {
            deal(underlying, user, amount);
            vm.startPrank(user);
            IERC20(underlying).approve(wrapperAddr, amount);
            wrapper.deposit(amount, user, referralCode, true);
            vm.stopPrank();
        } else {
            deal(aToken, user, amount);
            vm.startPrank(user);
            IERC20(aToken).approve(wrapperAddr, amount);
            wrapper.deposit(amount, user, referralCode, false);
            vm.stopPrank();
        }
    }

    function _advanceTime(uint256 secondsToAdvance) internal {
        vm.warp(block.timestamp + secondsToAdvance);
        vm.roll(block.number + (secondsToAdvance / 12) + 1);
    }

    function _singleReward(address reward) internal pure returns (address[] memory rewards) {
        rewards = new address[](1);
        rewards[0] = reward;
    }

    function deal(address token, address to, uint256 give) internal {
        stdstore.target(token).sig(IERC20.balanceOf.selector).with_key(to).checked_write(give);
    }

    function _deployWrapper() internal returns (address deployed, address selectedAToken) {
        address atokenEnv = vm.envOr("ATOKEN", address(0));
        address assetEnv = vm.envOr("ASSET", address(0));
        address proxyAdmin = vm.envOr("PROXY_ADMIN", address(0));
        address selectedAsset;

        if (atokenEnv == address(0)) {
            require(assetEnv != address(0), "ATOKEN_OR_ASSET_REQUIRED");
            selectedAsset = assetEnv;
            DataTypes.ReserveData memory data = IPool(NeverlandMonadMainnet.POOL).getReserveData(selectedAsset);
            selectedAToken = data.aTokenAddress;
            require(selectedAToken != address(0), "ATOKEN_NOT_FOUND");
        } else {
            selectedAToken = atokenEnv;
            selectedAsset = _resolveUnderlyingFromAddressBook(selectedAToken);
            require(selectedAsset != address(0), "ASSET_NOT_FOUND");
        }

        StaticATokenLM impl = new StaticATokenLM(
            IPool(NeverlandMonadMainnet.POOL), IRewardsController(NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER)
        );

        string memory aTokenSymbol = IERC20Metadata(selectedAToken).symbol();
        string memory underlyingSymbol = IERC20Metadata(selectedAsset).symbol();
        string memory name = string(abi.encodePacked("Wrapped Neverland ", underlyingSymbol));
        string memory symbol = string(abi.encodePacked("w", aTokenSymbol));

        bytes memory initData = abi.encodeWithSelector(StaticATokenLM.initialize.selector, selectedAToken, name, symbol);

        if (proxyAdmin == address(0)) {
            proxyAdmin = vm.addr(uint256(0xB0B));
        }

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdmin, initData);

        deployed = address(proxy);
    }

    function _resolveUnderlyingFromAddressBook(address atoken) internal pure returns (address) {
        if (atoken == NeverlandMonadMainnet.N_WMON) return NeverlandMonadMainnet.WMON;
        if (atoken == NeverlandMonadMainnet.N_USDC) return NeverlandMonadMainnet.USDC;
        if (atoken == NeverlandMonadMainnet.N_USDT0) return NeverlandMonadMainnet.USDT0;
        if (atoken == NeverlandMonadMainnet.N_WBTC) return NeverlandMonadMainnet.WBTC;
        if (atoken == NeverlandMonadMainnet.N_WETH) return NeverlandMonadMainnet.WETH;
        if (atoken == NeverlandMonadMainnet.N_SMON) return NeverlandMonadMainnet.SMON;
        if (atoken == NeverlandMonadMainnet.N_SHMON) return NeverlandMonadMainnet.SHMON;
        if (atoken == NeverlandMonadMainnet.N_GMON) return NeverlandMonadMainnet.GMON;
        if (atoken == NeverlandMonadMainnet.N_AUSD) return NeverlandMonadMainnet.AUSD;
        if (atoken == NeverlandMonadMainnet.N_EARNAUSD) return NeverlandMonadMainnet.EARNAUSD;
        if (atoken == NeverlandMonadMainnet.N_LOAZND) return NeverlandMonadMainnet.LOAZND;
        revert("ATOKEN_NOT_IN_ADDRESS_BOOK");
    }

    function _logRevert(string memory label, bytes memory reason) internal pure {
        console2.log("REVERT:", label);
        if (reason.length >= 4) {
            bytes4 selector;
            assembly {
                selector := mload(add(reason, 32))
            }
            console2.log("selector");
            console2.logBytes4(selector);
        }
        console2.logBytes(reason);
    }
}
