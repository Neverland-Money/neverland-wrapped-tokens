// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StaticATokenLM} from "../src/StaticATokenLM.sol";
import {IERC4626} from "../src/interfaces/IERC4626.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {IERC20Metadata} from "solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "solidity-utils/contracts/oz-common/SafeERC20.sol";
import {NeverlandMonadMainnet} from "../src/NeverlandAddressBook.sol";

/**
 * @title SmokeTestMainnet
 * @notice Minimal live smoke-test for a static token on Monad mainnet.
 * @dev Uses deployer private key to:
 *      - Approve + deposit small amount
 *      - (Optional) claim rewards (liquid)
 *      - (Optional) redeem back to underlying
 *
 * Env:
 *  - PRIVATE_KEY or DEPLOYER_PRIVATE_KEY (required)
 *  - STATIC_TOKEN (optional, default wnUSDC)
 *  - AMOUNT (optional, default 1 unit of underlying)
 *  - RECEIVER (optional, default deployer)
 *  - DO_DEPOSIT (0/1, default 1)
 *  - DO_CLAIM (0/1, default 1)
 *  - DO_REDEEM (0/1, default 1)
 */
contract SmokeTestMainnet is Script {
    using SafeERC20 for IERC20;

    function run() external {
        uint256 pk = _envOrPk("DEPLOYER_PRIVATE_KEY");
        if (pk == 0) {
            pk = _envOrPk("PRIVATE_KEY");
        }
        require(pk != 0, "Missing deployer private key");

        address user = vm.addr(pk);
        address receiver = _envOrAddress("RECEIVER", user);
        address staticTokenAddr = _envOrAddress("STATIC_TOKEN", NeverlandMonadMainnet.STATN_USDC);

        uint256 doDeposit = _envOrUint("DO_DEPOSIT", 1);
        uint256 doClaim = _envOrUint("DO_CLAIM", 1);
        uint256 doRedeem = _envOrUint("DO_REDEEM", 1);

        StaticATokenLM staticToken = StaticATokenLM(staticTokenAddr);
        address underlying = staticToken.asset();
        uint8 underlyingDecimals = IERC20Metadata(underlying).decimals();

        uint256 amount = _envOrUint("AMOUNT", 0);
        if (amount == 0) {
            amount = 10 ** uint256(underlyingDecimals);
        }

        console2.log("\n=== Smoke Test (Mainnet) ===");
        console2.log("User", user);
        console2.log("Receiver", receiver);
        console2.log("StaticToken", staticTokenAddr);
        console2.log("Underlying", underlying);
        console2.log("Amount", amount);
        console2.log("Symbol", IERC20Metadata(staticTokenAddr).symbol());
        console2.log("Name", IERC20Metadata(staticTokenAddr).name());
        console2.log("Decimals", IERC20Metadata(staticTokenAddr).decimals());

        uint256 underlyingBal = IERC20(underlying).balanceOf(user);
        console2.log("Underlying balance", underlyingBal);
        if (doDeposit == 1 && underlyingBal < amount) {
            console2.log("Insufficient underlying balance, aborting");
            return;
        }

        vm.startBroadcast(pk);

        if (doDeposit == 1) {
            _doDeposit(staticToken, staticTokenAddr, underlying, user, receiver, amount);
        } else {
            console2.log("Deposit skipped");
        }

        if (doClaim == 1) {
            _doClaim(staticToken, staticTokenAddr, receiver);
        } else {
            console2.log("Claim skipped");
        }

        if (doRedeem == 1) {
            _doRedeem(staticToken, staticTokenAddr, receiver);
        } else {
            console2.log("Redeem skipped");
        }

        vm.stopBroadcast();
    }

    function _envOrAddress(string memory key, address fallbackValue) internal view returns (address) {
        try vm.envAddress(key) returns (address value) {
            return value;
        } catch {
            return fallbackValue;
        }
    }

    function _envOrUint(string memory key, uint256 fallbackValue) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 value) {
            return value;
        } catch {
            return fallbackValue;
        }
    }

    function _envOrPk(string memory key) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 value) {
            return value;
        } catch {}
        try vm.envBytes32(key) returns (bytes32 value) {
            return uint256(value);
        } catch {}
        try vm.envString(key) returns (string memory value) {
            return vm.parseUint(value);
        } catch {}
        return 0;
    }

    function _doDeposit(
        StaticATokenLM staticToken,
        address staticTokenAddr,
        address underlying,
        address user,
        address receiver,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(underlying).allowance(user, staticTokenAddr);
        if (allowance < amount) {
            console2.log("Step: approve");
            _forceApprove(underlying, staticTokenAddr, amount, "approve");
            uint256 newAllowance = IERC20(underlying).allowance(user, staticTokenAddr);
            require(newAllowance >= amount, "approve did not set allowance");
        } else {
            console2.log("Step: approve (skipped, allowance sufficient)");
        }

        uint256 sharesBefore = staticToken.balanceOf(receiver);
        console2.log("Step: deposit");
        _callOrRevert(staticTokenAddr, abi.encodeCall(IERC4626.deposit, (amount, receiver)), "deposit");
        uint256 sharesAfter = staticToken.balanceOf(receiver);

        console2.log("Deposit shares minted", sharesAfter - sharesBefore);
    }

    function _doClaim(StaticATokenLM staticToken, address staticTokenAddr, address receiver) internal {
        address[] memory rewards = staticToken.rewardTokens();
        if (rewards.length == 0) {
            console2.log("No reward tokens registered, skipping claim");
            return;
        }

        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            uint256 claimable = staticToken.getClaimableRewards(receiver, rewards[i]);
            console2.log("Reward token", rewards[i]);
            console2.log("Claimable", claimable);
            totalClaimable += claimable;
        }

        if (totalClaimable == 0) {
            console2.log("All claimable rewards are 0, skipping claim");
            return;
        }

        uint256[] memory balancesBefore = new uint256[](rewards.length);
        for (uint256 i = 0; i < rewards.length; i++) {
            balancesBefore[i] = IERC20(rewards[i]).balanceOf(receiver);
        }

        console2.log("Step: claimRewards");
        _callOrRevert(
            staticTokenAddr,
            abi.encodeWithSelector(StaticATokenLM.claimRewards.selector, receiver, rewards),
            "claimRewards"
        );

        for (uint256 i = 0; i < rewards.length; i++) {
            uint256 afterBal = IERC20(rewards[i]).balanceOf(receiver);
            console2.log("Reward received", afterBal - balancesBefore[i]);
        }
    }

    function _doRedeem(StaticATokenLM staticToken, address staticTokenAddr, address receiver) internal {
        uint256 shares = staticToken.balanceOf(receiver);
        if (shares == 0) {
            console2.log("No shares to redeem, skipping");
            return;
        }

        console2.log("Step: redeem");
        _callOrRevert(staticTokenAddr, abi.encodeCall(IERC4626.redeem, (shares, receiver, receiver)), "redeem");
        console2.log("Redeemed shares", shares);
    }

    function _forceApprove(address token, address spender, uint256 amount, string memory label) internal {
        bytes memory approveCall = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);
        if (_callOptionalReturnBool(token, approveCall, label)) {
            return;
        }

        bytes memory resetCall = abi.encodeWithSelector(IERC20.approve.selector, spender, 0);
        _requireCall(token, resetCall, string(abi.encodePacked(label, " reset")));
        _requireCall(token, approveCall, label);
    }

    function _callOrRevert(address target, bytes memory data, string memory label) internal {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            _logRevert(label, returndata);
            revert(string(abi.encodePacked(label, " failed")));
        }
        // Do not attempt to decode return data here; the caller knows the ABI.
    }

    function _requireCall(address target, bytes memory data, string memory label) internal {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            _logRevert(label, returndata);
            revert(string(abi.encodePacked(label, " failed")));
        }
        if (returndata.length > 0) {
            if (returndata.length == 32 && !abi.decode(returndata, (bool))) {
                console2.log("%s failed: false return", label);
                revert(string(abi.encodePacked(label, " failed")));
            }
        }
    }

    function _callOptionalReturnBool(address token, bytes memory data, string memory label) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) {
            _logRevert(label, returndata);
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        if (returndata.length == 32) {
            return abi.decode(returndata, (bool));
        }
        return false;
    }

    function _logRevert(string memory label, bytes memory returndata) internal pure {
        if (returndata.length >= 4) {
            bytes4 selector;
            assembly {
                selector := mload(add(returndata, 0x20))
            }
            // Error(string)
            if (selector == 0x08c379a0 && returndata.length >= 68) {
                string memory reason;
                assembly {
                    reason := add(returndata, 0x68)
                }
                console2.log("%s revert: %s", label, reason);
                return;
            }
            // Panic(uint256)
            if (selector == 0x4e487b71 && returndata.length >= 36) {
                uint256 code;
                assembly {
                    code := mload(add(returndata, 0x24))
                }
                console2.log("%s panic code: %s", label, code);
                return;
            }
        }
        console2.log("%s reverted (no reason)", label);
    }
}
