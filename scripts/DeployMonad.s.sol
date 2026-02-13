// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {StaticATokenFactory} from "../src/StaticATokenFactory.sol";
import {StaticATokenLM} from "../src/StaticATokenLM.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol";
import {TransparentProxyFactory} from "solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol";
import {
    ITransparentProxyFactory
} from "solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol";
import {IAToken} from "../src/interfaces/IAToken.sol";

/**
 * @title DeployMonadMainnet
 * @notice Deployment script for Neverland's static aToken factory on Monad Mainnet
 * @dev This script deploys:
 *   1. ProxyAdmin for managing upgradeable contracts
 *   2. TransparentProxyFactory for creating deterministic proxies
 *   3. StaticATokenLM implementation
 *   4. StaticATokenFactory (implementation + proxy)
 *   5. Creates static aTokens for all reserves
 */
contract DeployMonadMainnet is Script {
    // Neverland Monad Mainnet Addresses
    address constant POOL = 0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585;
    address constant POOL_ADDRESSES_PROVIDER = 0x49D75170F55C964dfdd6726c74fdEDEe75553A0f;

    // Neverland's DustRewardsController
    address constant REWARDS_CONTROLLER = 0x57ea245cCbFAb074baBb9d01d1F0c60525E52cec;

    // Deployer will be the ProxyAdmin owner
    address deployer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        _preflightChecks();

        console.log("Deployer:", deployer);
        console.log("Pool:", POOL);
        console.log("DustRewardsController:", REWARDS_CONTROLLER);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy ProxyAdmin
        console.log("\n=== Deploying ProxyAdmin ===");
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        _maybeTransferProxyAdmin(proxyAdmin);

        // Step 2: Deploy TransparentProxyFactory
        console.log("\n=== Deploying TransparentProxyFactory ===");
        TransparentProxyFactory proxyFactory = new TransparentProxyFactory();
        console.log("TransparentProxyFactory deployed at:", address(proxyFactory));

        // Step 3: Deploy StaticATokenLM implementation
        console.log("\n=== Deploying StaticATokenLM Implementation ===");
        StaticATokenLM staticImpl = new StaticATokenLM(IPool(POOL), IRewardsController(REWARDS_CONTROLLER));
        console.log("StaticATokenLM implementation deployed at:", address(staticImpl));

        // Step 4: Deploy StaticATokenFactory implementation
        console.log("\n=== Deploying StaticATokenFactory Implementation ===");
        StaticATokenFactory factoryImpl = new StaticATokenFactory(
            IPool(POOL), address(proxyAdmin), ITransparentProxyFactory(address(proxyFactory)), address(staticImpl)
        );
        console.log("StaticATokenFactory implementation deployed at:", address(factoryImpl));

        console.log("");
        console.log("  PROXY_ADMIN =", address(proxyAdmin));
        console.log("  TRANSPARENT_PROXY_FACTORY =", address(proxyFactory));
        console.log("  STATIC_A_TOKEN_IMPL =", address(staticImpl));
        console.log("  STATIC_A_TOKEN_FACTORY will be shown after proxy deployment");
        console.log("");

        // Step 5: Deploy StaticATokenFactory proxy
        console.log("\n=== Deploying StaticATokenFactory Proxy ===");
        bytes memory initData = abi.encodeWithSelector(StaticATokenFactory.initialize.selector);
        TransparentUpgradeableProxy factoryProxy =
            new TransparentUpgradeableProxy(address(factoryImpl), address(proxyAdmin), initData);
        console.log("StaticATokenFactory proxy deployed at:", address(factoryProxy));

        StaticATokenFactory factory = StaticATokenFactory(address(factoryProxy));

        // Step 6: Get all reserves and create static aTokens
        console.log("\n=== Creating Static ATokens for all reserves ===");
        address[] memory reserves = IPool(POOL).getReservesList();
        console.log("Number of reserves:", reserves.length);

        uint256 batchSize = _envUintOrZero("BATCH_SIZE");
        address[] memory staticATokens = _createStaticATokens(factory, reserves, batchSize);

        console.log("\n=== Deployment Summary ===");
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("TransparentProxyFactory:", address(proxyFactory));
        console.log("StaticATokenLM Implementation:", address(staticImpl));
        console.log("StaticATokenFactory Implementation:", address(factoryImpl));
        console.log("StaticATokenFactory Proxy:", address(factoryProxy));
        console.log("\nStatic ATokens created:");
        for (uint256 i = 0; i < reserves.length; i++) {
            console.log("- Reserve:", reserves[i]);
            console.log("  Static AToken:", staticATokens[i]);
        }

        vm.stopBroadcast();

        console.log("\n=== Quick Verification Setup ===");
        console.log("Copy and paste these commands to verify deployment:\n");
        console.log("export PROXY_ADMIN=%s", address(proxyAdmin));
        console.log("export TRANSPARENT_PROXY_FACTORY=%s", address(proxyFactory));
        console.log("export STATIC_A_TOKEN_IMPL=%s", address(staticImpl));
        console.log("export STATIC_A_TOKEN_FACTORY_IMPL=%s", address(factoryImpl));
        console.log("export STATIC_A_TOKEN_FACTORY=%s", address(factoryProxy));
        console.log("\nThen run:");
        console.log("forge script scripts/VerifyDeployment.s.sol:VerifyDeployment --rpc-url monad -vvv");
        console.log("");
    }

    function _preflightChecks() internal view {
        if (!_envBool("SKIP_CHAINID_CHECK")) {
            uint256 expectedChainId = _envUintOr("EXPECTED_CHAIN_ID", 143);
            require(block.chainid == expectedChainId, "WRONG_CHAIN_ID");
        }

        _requireContract(POOL, "Pool");
        _requireContract(POOL_ADDRESSES_PROVIDER, "PoolAddressesProvider");
        _requireContract(REWARDS_CONTROLLER, "RewardsController");

        address providerPool = IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER).getPool();
        require(providerPool == POOL, "PROVIDER_POOL_MISMATCH");

        address[] memory reserves = IPool(POOL).getReservesList();
        require(reserves.length > 0, "NO_RESERVES");

        if (!_envBool("SKIP_INCENTIVES_CHECK") && REWARDS_CONTROLLER != address(0)) {
            for (uint256 i = 0; i < reserves.length; i++) {
                DataTypes.ReserveData memory data = IPool(POOL).getReserveData(reserves[i]);
                require(data.aTokenAddress != address(0), "RESERVE_NOT_LISTED");
                address incentives = IAToken(data.aTokenAddress).getIncentivesController();
                if (incentives != REWARDS_CONTROLLER) {
                    console.log("Incentives mismatch for reserve:", reserves[i]);
                    console.log("  aToken:", data.aTokenAddress);
                    console.log("  Expected:", REWARDS_CONTROLLER);
                    console.log("  Got:", incentives);
                    revert("INCENTIVES_CONTROLLER_MISMATCH");
                }
            }
        }
    }

    function _createStaticATokens(StaticATokenFactory factory, address[] memory reserves, uint256 batchSize)
        internal
        returns (address[] memory)
    {
        if (batchSize == 0 || batchSize >= reserves.length) {
            return factory.createStaticATokens(reserves);
        }

        address[] memory allStaticTokens = new address[](reserves.length);
        uint256 i = 0;
        while (i < reserves.length) {
            uint256 remaining = reserves.length - i;
            uint256 len = batchSize < remaining ? batchSize : remaining;
            address[] memory batch = new address[](len);
            for (uint256 j = 0; j < len; j++) {
                batch[j] = reserves[i + j];
            }

            console.log("  Deploying batch: %s - %s", i, i + len - 1);
            address[] memory deployed = factory.createStaticATokens(batch);
            for (uint256 j = 0; j < len; j++) {
                allStaticTokens[i + j] = deployed[j];
            }
            i += len;
        }

        return allStaticTokens;
    }

    function _maybeTransferProxyAdmin(ProxyAdmin proxyAdmin) internal {
        address newOwner = _envAddressOrZero("PROXY_ADMIN_OWNER");
        if (newOwner != address(0) && newOwner != deployer) {
            console.log("Transferring ProxyAdmin ownership to:", newOwner);
            proxyAdmin.transferOwnership(newOwner);
        }
    }

    function _requireContract(address addr, string memory name) internal view {
        require(addr != address(0), "ZERO_ADDRESS");
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        require(size > 0, string(abi.encodePacked(name, "_NO_CODE")));
    }

    function _envAddressOrZero(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address value) {
            return value;
        } catch {
            return address(0);
        }
    }

    function _envUintOrZero(string memory key) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 value) {
            return value;
        } catch {
            return 0;
        }
    }

    function _envUintOr(string memory key, uint256 fallbackValue) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 value) {
            return value;
        } catch {
            return fallbackValue;
        }
    }

    function _envBool(string memory key) internal view returns (bool) {
        try vm.envBool(key) returns (bool value) {
            return value;
        } catch {
            return false;
        }
    }
}
