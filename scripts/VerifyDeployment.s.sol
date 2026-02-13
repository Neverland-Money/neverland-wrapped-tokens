// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {StaticATokenFactory} from "../src/StaticATokenFactory.sol";
import {StaticATokenLM} from "../src/StaticATokenLM.sol";
import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {IERC20Metadata} from "solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol";
import {ProxyAdmin} from "solidity-utils/contracts/transparent-proxy/ProxyAdmin.sol";
import {
    ITransparentProxyFactory
} from "solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol";
import {IAToken} from "../src/interfaces/IAToken.sol";

/**
 * @title VerifyDeployment
 * @notice Post-deployment verification script for Neverland's static aToken deployment
 * @dev Validates all deployed contracts on Monad mainnet:
 *      - Bytecode verification
 *      - Configuration checks
 *      - Token metadata validation
 *      - Basic functionality tests
 *
 * Usage:
 *   forge script scripts/VerifyDeployment.s.sol:VerifyDeployment \
 *     --rpc-url monad \
 *     -vvv
 */
contract VerifyDeployment is Script {
    // ============================================
    // DEPLOYMENT ADDRESSES (UPDATE AFTER DEPLOY)
    // ============================================

    address constant DEFAULT_PROXY_ADMIN = address(0); // UPDATE OR SET ENV
    address constant DEFAULT_TRANSPARENT_PROXY_FACTORY = address(0); // UPDATE OR SET ENV
    address constant DEFAULT_STATIC_A_TOKEN_IMPL = address(0); // UPDATE OR SET ENV
    address constant DEFAULT_STATIC_A_TOKEN_FACTORY = address(0); // UPDATE OR SET ENV

    // Resolved deployment addresses (env overrides constants)
    address internal PROXY_ADMIN;
    address internal TRANSPARENT_PROXY_FACTORY;
    address internal STATIC_A_TOKEN_IMPL;
    address internal STATIC_A_TOKEN_FACTORY;

    // ============================================
    // EXPECTED VALUES
    // ============================================

    address constant EXPECTED_POOL = 0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585;
    address constant EXPECTED_REWARDS_CONTROLLER = 0x57ea245cCbFAb074baBb9d01d1F0c60525E52cec;
    address constant DEFAULT_EXPECTED_DEPLOYER = 0x57976e192C45461F5958045a0bC57102e90440eD;
    address internal EXPECTED_DEPLOYER;

    // Reserve addresses
    address constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address constant USDT0 = 0xe7cd86e13AC4309349F30B3435a9d337750fC82D;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address constant WETH = 0xEE8c0E9f1BFFb4Eb878d8f15f368A02a35481242;
    address constant SMON = 0xA3227C5969757783154C60bF0bC1944180ed81B9;
    address constant SHMON = 0x1B68626dCa36c7fE922fD2d55E4f631d962dE19c;
    address constant GMON = 0x8498312A6B3CbD158bf0c93AbdCF29E6e4F55081;
    address constant AUSD = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
    address constant EARNAUSD = 0x103222f020e98Bba0AD9809A011FDF8e6F067496;
    address constant LOAZND = 0x9c82eB49B51F7Dc61e22Ff347931CA32aDc6cd90;

    // nToken addresses
    address constant N_WMON = 0xD0fd2Cf7F6CEff4F96B1161F5E995D5843326154;
    address constant N_USDC = 0x38648958836eA88b368b4ac23b86Ad44B0fe7508;
    address constant N_USDT0 = 0x39F901c32b2E0d25AE8DEaa1ee115C748f8f6bDf;
    address constant N_WBTC = 0x34c43684293963c546b0aB6841008A4d3393B9ab;
    address constant N_WETH = 0x31f63Ae5a96566b93477191778606BeBDC4CA66f;
    address constant N_SMON = 0xdFC14d336aea9E49113b1356333FD374e646Bf85;
    address constant N_SHMON = 0xC64d73Bb8748C6fA7487ace2D0d945B6fBb2EcDe;
    address constant N_GMON = 0x7f81779736968836582D31D36274Ed82053aD1AE;
    address constant N_AUSD = 0x784999fc2Dd132a41D1Cc0F1aE9805854BaD1f2D;
    address constant N_EARNAUSD = 0xaCaaA891b30E13D024AB67b6EcA9c2EcBD8cf52b;
    address constant N_LOAZND = 0x293e2f01a38Fe690Eb8E570AB952b24b225113a7;

    // Factory cache
    StaticATokenFactory internal _factory;
    bool internal _factoryReady;

    // Tracking
    uint256 public totalTests;
    uint256 public passedTests;
    uint256 public failedTests;

    function run() external {
        _loadDeploymentAddresses();

        console.log("\n========================================");
        console.log("Static AToken Deployment Verification");
        console.log("========================================\n");

        _verifyProxyAdmin();
        _verifyTransparentProxyFactory();
        _verifyStaticATokenImpl();
        _verifyStaticATokenFactory();
        _verifyAllStaticTokens();

        _printSummary();
    }

    function _loadDeploymentAddresses() internal {
        PROXY_ADMIN = _envOrAddress("PROXY_ADMIN", DEFAULT_PROXY_ADMIN);
        TRANSPARENT_PROXY_FACTORY = _envOrAddress("TRANSPARENT_PROXY_FACTORY", DEFAULT_TRANSPARENT_PROXY_FACTORY);
        STATIC_A_TOKEN_IMPL = _envOrAddress("STATIC_A_TOKEN_IMPL", DEFAULT_STATIC_A_TOKEN_IMPL);
        STATIC_A_TOKEN_FACTORY = _envOrAddress("STATIC_A_TOKEN_FACTORY", DEFAULT_STATIC_A_TOKEN_FACTORY);
        EXPECTED_DEPLOYER = _envOrAddress("EXPECTED_DEPLOYER", DEFAULT_EXPECTED_DEPLOYER);

        console.log("Deployment addresses:");
        _logAddress("PROXY_ADMIN", PROXY_ADMIN);
        _logAddress("TRANSPARENT_PROXY_FACTORY", TRANSPARENT_PROXY_FACTORY);
        _logAddress("STATIC_A_TOKEN_IMPL", STATIC_A_TOKEN_IMPL);
        _logAddress("STATIC_A_TOKEN_FACTORY", STATIC_A_TOKEN_FACTORY);
        _logAddress("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        console.log("");
    }

    // ============================================
    // VERIFICATION FUNCTIONS
    // ============================================

    function _verifyProxyAdmin() internal {
        console.log("=== ProxyAdmin Verification ===");

        if (!_checkContractExists(PROXY_ADMIN, "ProxyAdmin")) {
            console.log("  [SKIP]: ProxyAdmin checks skipped");
            console.log("");
            return;
        }

        ProxyAdmin proxyAdmin = ProxyAdmin(PROXY_ADMIN);
        try proxyAdmin.owner() returns (address owner) {
            _assertEqual(owner, EXPECTED_DEPLOYER, "ProxyAdmin owner");
        } catch {
            _failCall("ProxyAdmin owner()");
        }

        console.log("ProxyAdmin verified\n");
    }

    function _verifyTransparentProxyFactory() internal {
        console.log("=== TransparentProxyFactory Verification ===");

        if (!_checkContractExists(TRANSPARENT_PROXY_FACTORY, "TransparentProxyFactory")) {
            console.log("  [SKIP]: TransparentProxyFactory checks skipped");
            console.log("");
            return;
        }

        console.log("TransparentProxyFactory verified\n");
    }

    function _verifyStaticATokenImpl() internal {
        console.log("=== StaticATokenLM Implementation Verification ===");

        if (!_checkContractExists(STATIC_A_TOKEN_IMPL, "StaticATokenLM")) {
            console.log("  [SKIP]: StaticATokenLM checks skipped");
            console.log("");
            return;
        }

        StaticATokenLM impl = StaticATokenLM(STATIC_A_TOKEN_IMPL);

        try impl.POOL() returns (IPool pool) {
            _assertEqual(address(pool), EXPECTED_POOL, "Pool address");
        } catch {
            _failCall("StaticATokenLM.POOL()");
        }

        try impl.INCENTIVES_CONTROLLER() returns (IRewardsController rewardsController) {
            _assertEqual(address(rewardsController), EXPECTED_REWARDS_CONTROLLER, "RewardsController");
        } catch {
            _failCall("StaticATokenLM.INCENTIVES_CONTROLLER()");
        }

        console.log("StaticATokenLM implementation verified\n");
    }

    function _verifyStaticATokenFactory() internal {
        console.log("=== StaticATokenFactory Verification ===");

        if (!_checkContractExists(STATIC_A_TOKEN_FACTORY, "StaticATokenFactory")) {
            console.log("  [SKIP]: StaticATokenFactory checks skipped");
            console.log("");
            return;
        }

        _factory = StaticATokenFactory(STATIC_A_TOKEN_FACTORY);
        _factoryReady = true;

        try _factory.POOL() returns (IPool pool) {
            _assertEqual(address(pool), EXPECTED_POOL, "Factory Pool");
        } catch {
            _failCall("Factory.POOL()");
        }

        try _factory.ADMIN() returns (address admin) {
            _assertEqual(admin, PROXY_ADMIN, "Factory Admin");
        } catch {
            _failCall("Factory.ADMIN()");
        }

        try _factory.TRANSPARENT_PROXY_FACTORY() returns (ITransparentProxyFactory proxyFactory) {
            _assertEqual(address(proxyFactory), TRANSPARENT_PROXY_FACTORY, "Factory ProxyFactory");
        } catch {
            _failCall("Factory.TRANSPARENT_PROXY_FACTORY()");
        }

        try _factory.STATIC_A_TOKEN_IMPL() returns (address impl) {
            _assertEqual(impl, STATIC_A_TOKEN_IMPL, "Factory Impl");
        } catch {
            _failCall("Factory.STATIC_A_TOKEN_IMPL()");
        }

        console.log("StaticATokenFactory verified\n");
    }

    function _verifyAllStaticTokens() internal {
        console.log("=== Static Tokens Verification ===\n");

        if (!_factoryReady) {
            console.log("  [SKIP]: Static token checks skipped (factory not verified)");
            console.log("");
            return;
        }

        _verifyStaticToken(WMON, N_WMON, "nWMON");
        _verifyStaticToken(USDC, N_USDC, "nUSDC");
        _verifyStaticToken(USDT0, N_USDT0, "nUSDT0");
        _verifyStaticToken(WBTC, N_WBTC, "nWBTC");
        _verifyStaticToken(WETH, N_WETH, "nWETH");
        _verifyStaticToken(SMON, N_SMON, "nSMON");
        _verifyStaticToken(SHMON, N_SHMON, "nSHMON");
        _verifyStaticToken(GMON, N_GMON, "nGMON");
        _verifyStaticToken(AUSD, N_AUSD, "nAUSD");
        _verifyStaticToken(EARNAUSD, N_EARNAUSD, "nEARNAUSD");
        _verifyStaticToken(LOAZND, N_LOAZND, "nLOAZND");

        console.log("All static tokens verified\n");
    }

    function _verifyStaticToken(address underlying, address expectedNToken, string memory expectedNTokenSymbol)
        internal
    {
        console.log("Verifying static token for: %s", underlying);

        address staticToken;
        try _factory.getStaticAToken(underlying) returns (address tokenAddr) {
            staticToken = tokenAddr;
        } catch {
            _failCall("Factory.getStaticAToken()");
            console.log("");
            return;
        }

        if (staticToken == address(0)) {
            console.log("  [FAIL]: Static token not deployed for underlying");
            console.log("    Underlying: %s", underlying);
            failedTests++;
            totalTests++;
            console.log("");
            return;
        }

        if (!_checkContractExists(staticToken, "StaticAToken")) {
            console.log("");
            return;
        }

        StaticATokenLM token = StaticATokenLM(staticToken);

        // Verify aToken
        address aToken;
        try token.aToken() returns (IERC20 aTokenRef) {
            aToken = address(aTokenRef);
            _assertEqual(aToken, expectedNToken, "nToken address");
        } catch {
            _failCall("StaticAToken.aToken()");
            console.log("");
            return;
        }

        // Verify aToken symbol matches expected
        string memory aTokenSymbol;
        try IERC20Metadata(aToken).symbol() returns (string memory symbol) {
            aTokenSymbol = symbol;
            _assertStringEqual(aTokenSymbol, expectedNTokenSymbol, "nToken symbol");
        } catch {
            _failCall("nToken.symbol()");
        }

        // Compute expected static token metadata
        string memory underlyingSymbol;
        try IERC20Metadata(underlying).symbol() returns (string memory symbol) {
            underlyingSymbol = symbol;
        } catch {
            _failCall("Underlying.symbol()");
        }

        string memory expectedSymbol = string(abi.encodePacked("w", aTokenSymbol));
        string memory expectedName = string(abi.encodePacked("Wrapped Neverland ", underlyingSymbol));

        // Verify metadata
        try token.symbol() returns (string memory symbol) {
            _assertStringEqual(symbol, expectedSymbol, "Static token symbol");
        } catch {
            _failCall("StaticAToken.symbol()");
        }

        try token.name() returns (string memory name) {
            _assertStringEqual(name, expectedName, "Static token name");
        } catch {
            _failCall("StaticAToken.name()");
        }

        uint8 decimals;
        try token.decimals() returns (uint8 decs) {
            decimals = decs;
        } catch {
            _failCall("StaticAToken.decimals()");
        }

        // Verify underlying
        try token.asset() returns (address tokenUnderlying) {
            _assertEqual(tokenUnderlying, underlying, "Underlying asset");
        } catch {
            _failCall("StaticAToken.asset()");
        }

        // Verify decimals match underlying
        try IERC20Metadata(underlying).decimals() returns (uint8 underlyingDecimals) {
            _assertUint(decimals, underlyingDecimals, "Decimals");
        } catch {
            _failCall("Underlying.decimals()");
        }

        // Verify pool reference
        try token.POOL() returns (IPool pool) {
            _assertEqual(address(pool), EXPECTED_POOL, "Pool reference");
        } catch {
            _failCall("StaticAToken.POOL()");
        }

        // Verify rewards controller on StaticATokenLM
        try token.INCENTIVES_CONTROLLER() returns (IRewardsController rewardsController) {
            _assertEqual(address(rewardsController), EXPECTED_REWARDS_CONTROLLER, "Rewards controller");
        } catch {
            _failCall("StaticAToken.INCENTIVES_CONTROLLER()");
        }

        // Verify aToken incentives controller (must be updated post-deploy)
        try IAToken(aToken).getIncentivesController() returns (address incentivesController) {
            _assertEqual(incentivesController, EXPECTED_REWARDS_CONTROLLER, "nToken incentives controller");
        } catch {
            _failCall("nToken.getIncentivesController()");
        }

        console.log("  Static Token: %s", staticToken);
        console.log("  [VERIFIED]");
        console.log("");
    }

    // ============================================
    // ASSERTION HELPERS
    // ============================================

    function _checkContractExists(address addr, string memory name) internal returns (bool) {
        if (addr == address(0)) {
            console.log("  [FAIL]: %s is zero address", name);
            failedTests++;
            totalTests++;
            return false;
        }
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }

        if (size == 0) {
            console.log("  [FAIL]: %s has no bytecode", name);
            console.log("  Address: %s", addr);
            failedTests++;
            totalTests++;
            return false;
        } else {
            console.log("  [PASS]: %s exists with %s bytes", name, size);
            console.log("  Address: %s", addr);
            passedTests++;
            totalTests++;
            return true;
        }
    }

    function _assertEqual(address actual, address expected, string memory name) internal {
        if (actual != expected) {
            console.log("  [FAIL]: %s", name);
            console.log("    Expected: %s", expected);
            console.log("    Got: %s", actual);
            failedTests++;
        } else {
            console.log("  [PASS]: %s matches", name);
            passedTests++;
        }
        totalTests++;
    }

    function _assertStringEqual(string memory actual, string memory expected, string memory name) internal {
        if (keccak256(bytes(actual)) != keccak256(bytes(expected))) {
            console.log("  [FAIL]: %s", name);
            console.log("    Expected: %s", expected);
            console.log("    Got: %s", actual);
            failedTests++;
        } else {
            console.log("  [PASS]: %s = %s", name, actual);
            passedTests++;
        }
        totalTests++;
    }

    function _assertUint(uint256 actual, uint256 expected, string memory name) internal {
        if (actual != expected) {
            console.log("  [FAIL]: %s", name);
            console.log("    Expected: %s", expected);
            console.log("    Got: %s", actual);
            failedTests++;
        } else {
            console.log("  [PASS]: %s = %s", name, actual);
            passedTests++;
        }
        totalTests++;
    }

    function _failCall(string memory name) internal {
        console.log("  [FAIL]: %s call reverted", name);
        failedTests++;
        totalTests++;
    }

    function _envOrAddress(string memory key, address fallbackValue) internal view returns (address) {
        try vm.envAddress(key) returns (address value) {
            return value;
        } catch {
            return fallbackValue;
        }
    }

    function _logAddress(string memory label, address value) internal view {
        if (value == address(0)) {
            console.log("  %s: [UNSET]", label);
        } else {
            console.log("  %s: %s", label, value);
        }
    }

    function _printSummary() internal view {
        console.log("");
        console.log("========================================");
        console.log("Verification Summary");
        console.log("========================================");
        console.log("Total Tests: %s", totalTests);
        console.log("Passed: %s", passedTests);
        console.log("Failed: %s", failedTests);
        console.log("");

        if (failedTests == 0) {
            console.log("[SUCCESS] ALL TESTS PASSED - Deployment verified!");
        } else {
            console.log("[FAILED] SOME TESTS FAILED - Review deployment!");
        }
        console.log("========================================");
        console.log("");
    }
}
