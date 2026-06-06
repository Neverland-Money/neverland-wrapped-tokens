// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {IPoolAddressesProvider} from 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';
import {IAToken} from '../src/interfaces/IAToken.sol';

/**
 * @title VerifyPreDeployment
 * @notice Pre-deployment validation script for Neverland's static aToken deployment
 * @dev Validates BEFORE deployment to catch issues early:
 *      - Neverland infrastructure exists (Pool, RewardsController, nTokens)
 *      - All reserve addresses are valid
 *      - nToken symbols match expectations
 *      - Deployer has sufficient balance
 *      - Configuration is correct
 *
 * Usage:
 *   forge script scripts/VerifyPreDeployment.s.sol:VerifyPreDeployment \
 *     --rpc-url monad \
 *     -vvv
 */
contract VerifyPreDeployment is Script {
  // ============================================
  // NEVERLAND INFRASTRUCTURE
  // ============================================

  address constant POOL = 0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585;
  address constant POOL_ADDRESSES_PROVIDER = 0x49D75170F55C964dfdd6726c74fdEDEe75553A0f;
  address constant REWARDS_CONTROLLER = 0x57ea245cCbFAb074baBb9d01d1F0c60525E52cec;
  address constant DEPLOYER = 0x0000B06460777398083CB501793a4d6393900000;

  // ============================================
  // RESERVE CONFIGURATION
  // ============================================

  struct ReserveConfig {
    address underlying;
    address nToken;
    string expectedSymbol;
    uint8 expectedDecimals;
  }

  ReserveConfig[] public reserves;

  // Tracking
  uint256 public totalTests;
  uint256 public passedTests;
  uint256 public failedTests;

  function setUp() public {
    // Configure all reserves
    reserves.push(
      ReserveConfig({
        underlying: 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A,
        nToken: 0xD0fd2Cf7F6CEff4F96B1161F5E995D5843326154,
        expectedSymbol: 'nWMON',
        expectedDecimals: 18
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x754704Bc059F8C67012fEd69BC8A327a5aafb603,
        nToken: 0x38648958836eA88b368b4ac23b86Ad44B0fe7508,
        expectedSymbol: 'nUSDC',
        expectedDecimals: 6
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0xe7cd86e13AC4309349F30B3435a9d337750fC82D,
        nToken: 0x39F901c32b2E0d25AE8DEaa1ee115C748f8f6bDf,
        expectedSymbol: 'nUSDT0',
        expectedDecimals: 6
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c,
        nToken: 0x34c43684293963c546b0aB6841008A4d3393B9ab,
        expectedSymbol: 'nWBTC',
        expectedDecimals: 8
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0xEE8c0E9f1BFFb4Eb878d8f15f368A02a35481242,
        nToken: 0x31f63Ae5a96566b93477191778606BeBDC4CA66f,
        expectedSymbol: 'nWETH',
        expectedDecimals: 18
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0xA3227C5969757783154C60bF0bC1944180ed81B9,
        nToken: 0xdFC14d336aea9E49113b1356333FD374e646Bf85,
        expectedSymbol: 'nSMON',
        expectedDecimals: 18
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x1B68626dCa36c7fE922fD2d55E4f631d962dE19c,
        nToken: 0xC64d73Bb8748C6fA7487ace2D0d945B6fBb2EcDe,
        expectedSymbol: 'nSHMON',
        expectedDecimals: 18
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x8498312A6B3CbD158bf0c93AbdCF29E6e4F55081,
        nToken: 0x7f81779736968836582D31D36274Ed82053aD1AE,
        expectedSymbol: 'nGMON',
        expectedDecimals: 18
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a,
        nToken: 0x784999fc2Dd132a41D1Cc0F1aE9805854BaD1f2D,
        expectedSymbol: 'nAUSD',
        expectedDecimals: 6
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x103222f020e98Bba0AD9809A011FDF8e6F067496,
        nToken: 0xaCaaA891b30E13D024AB67b6EcA9c2EcBD8cf52b,
        expectedSymbol: 'nEARNAUSD',
        expectedDecimals: 6
      })
    );

    reserves.push(
      ReserveConfig({
        underlying: 0x9c82eB49B51F7Dc61e22Ff347931CA32aDc6cd90,
        nToken: 0x293e2f01a38Fe690Eb8E570AB952b24b225113a7,
        expectedSymbol: 'nLOAZND',
        expectedDecimals: 18
      })
    );
  }

  function run() external {
    console.log('');
    console.log('========================================');
    console.log('Pre-Deployment Verification');
    console.log('========================================');
    console.log('');

    _verifyInfrastructure();
    _verifyDeployerBalance();
    _verifyReserves();
    _verifyPoolConfiguration();

    _printSummary();
  }

  // ============================================
  // VERIFICATION FUNCTIONS
  // ============================================

  function _verifyInfrastructure() internal {
    console.log('=== Neverland Infrastructure Verification ===');

    // Check contracts exist
    _checkContractExists(POOL, 'Neverland Pool');
    _checkContractExists(POOL_ADDRESSES_PROVIDER, 'Pool Addresses Provider');
    _checkContractExists(REWARDS_CONTROLLER, 'DustRewardsController');

    // Verify Pool functionality
    IPool pool = IPool(POOL);
    address[] memory poolReserves;

    try pool.getReservesList() returns (address[] memory retrievedReserves) {
      poolReserves = retrievedReserves;
      if (retrievedReserves.length == 0) {
        console.log('  [FAIL]: Pool has no reserves listed');
        failedTests++;
      } else {
        console.log('  [PASS]: Pool has %s reserves', retrievedReserves.length);
        passedTests++;
      }
    } catch {
      console.log('  [FAIL]: Cannot call Pool.getReservesList()');
      failedTests++;
    }
    totalTests++;

    // Verify PoolAddressesProvider points to the expected Pool
    try IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER).getPool() returns (address providerPool) {
      _assertEqual(providerPool, POOL, 'PoolAddressesProvider.getPool()');
    } catch {
      console.log('  [FAIL]: Cannot call PoolAddressesProvider.getPool()');
      failedTests++;
      totalTests++;
    }

    // Reserve count sanity check (warn only if extra reserves)
    if (poolReserves.length < reserves.length) {
      console.log('  [FAIL]: Pool has fewer reserves than expected');
      console.log('    Expected at least: %s', reserves.length);
      console.log('    Got: %s', poolReserves.length);
      failedTests++;
    } else {
      console.log(
        '  [PASS]: Pool has %s reserves (expected at least %s)',
        poolReserves.length,
        reserves.length
      );
      passedTests++;
      if (poolReserves.length > reserves.length) {
        console.log('  [WARN]: Pool has extra reserves not listed in this script');
      }
    }
    totalTests++;

    // Verify deployer address
    uint256 deployerCodeSize;
    assembly {
      deployerCodeSize := extcodesize(DEPLOYER)
    }
    if (deployerCodeSize == 0) {
      console.log('  [PASS]: Deployer is EOA');
      passedTests++;
    } else {
      console.log('  [WARN]: Deployer is a contract (%s bytes)', deployerCodeSize);
      console.log('    This is fine if using a multisig/safe');
      passedTests++;
    }
    totalTests++;

    // Verify deployer matches env PRIVATE_KEY if provided
    address envDeployer = _getEnvDeployer();
    if (envDeployer != address(0)) {
      _assertEqual(envDeployer, DEPLOYER, 'Env deployer matches DEPLOYER');
    } else {
      console.log('  [WARN]: PRIVATE_KEY not set; skipping deployer match check');
    }

    console.log('');
  }

  function _verifyDeployerBalance() internal {
    console.log('=== Deployer Balance Verification ===');

    address deployerToCheck = _getEnvDeployer();
    if (deployerToCheck == address(0)) {
      deployerToCheck = DEPLOYER;
    }
    uint256 balance = deployerToCheck.balance;
    console.log('  Deployer address: %s', deployerToCheck);
    console.log('  Current balance: %s MON', balance / 1e18);

    // Minimum recommended balance for deployment
    uint256 estimatedCost = 0.5 ether; // 0.5 MON should be sufficient

    if (balance < estimatedCost) {
      console.log('  [WARN]: Balance may be insufficient for deployment');
      console.log('    Minimum recommended: %s MON', estimatedCost / 1e18);
      console.log('    Current balance: %s MON', balance / 1e18);
      failedTests++;
    } else {
      console.log('  [PASS]: Sufficient balance for deployment');
      passedTests++;
    }
    totalTests++;

    console.log('');
  }

  function _verifyReserves() internal {
    console.log('=== Reserve Assets Verification ===');
    console.log('');

    for (uint256 i = 0; i < reserves.length; i++) {
      ReserveConfig memory config = reserves[i];
      _verifyReserve(config);
    }

    console.log('All reserves verified');
    console.log('');
  }

  function _verifyReserve(ReserveConfig memory config) internal {
    console.log('Verifying reserve: %s', config.underlying);

    // Check underlying exists
    _checkContractExists(config.underlying, 'Underlying token');

    // Check nToken exists
    _checkContractExists(config.nToken, 'nToken');

    // Verify nToken underlying matches expected reserve
    try IAToken(config.nToken).UNDERLYING_ASSET_ADDRESS() returns (address underlyingAsset) {
      _assertEqual(underlyingAsset, config.underlying, 'nToken underlying');
    } catch {
      console.log('  [FAIL]: Cannot read nToken underlying asset');
      failedTests++;
      totalTests++;
    }

    // Verify nToken incentives controller
    try IAToken(config.nToken).getIncentivesController() returns (address incentivesController) {
      if (incentivesController == REWARDS_CONTROLLER) {
        console.log('  [PASS]: nToken incentives controller set');
        passedTests++;
      } else {
        console.log('  [FAIL]: nToken incentives controller mismatch');
        console.log('    Expected: %s', REWARDS_CONTROLLER);
        console.log('    Got: %s', incentivesController);
        failedTests++;
      }
      totalTests++;
    } catch {
      console.log('  [FAIL]: Cannot read nToken incentives controller');
      failedTests++;
      totalTests++;
    }

    // Verify nToken symbol
    try IERC20Metadata(config.nToken).symbol() returns (string memory symbol) {
      if (keccak256(bytes(symbol)) == keccak256(bytes(config.expectedSymbol))) {
        console.log('  [PASS]: nToken symbol = %s', symbol);
        passedTests++;
      } else {
        console.log('  [FAIL]: nToken symbol mismatch');
        console.log('    Expected: %s', config.expectedSymbol);
        console.log('    Got: %s', symbol);
        failedTests++;
      }
      totalTests++;
    } catch {
      console.log('  [FAIL]: Cannot read nToken symbol');
      failedTests++;
      totalTests++;
    }

    // Verify underlying decimals
    try IERC20Metadata(config.underlying).decimals() returns (uint8 decimals) {
      if (decimals == config.expectedDecimals) {
        console.log('  [PASS]: Decimals = %s', decimals);
        passedTests++;
      } else {
        console.log('  [FAIL]: Decimals mismatch');
        console.log('    Expected: %s', config.expectedDecimals);
        console.log('    Got: %s', decimals);
        failedTests++;
      }
      totalTests++;
    } catch {
      console.log('  [FAIL]: Cannot read decimals');
      failedTests++;
      totalTests++;
    }

    console.log('');
  }

  function _verifyPoolConfiguration() internal {
    console.log('=== Pool Configuration Verification ===');

    IPool pool = IPool(POOL);

    // Verify all our reserves are listed in the pool
    address[] memory poolReserves = pool.getReservesList();

    for (uint256 i = 0; i < reserves.length; i++) {
      bool found = false;
      for (uint256 j = 0; j < poolReserves.length; j++) {
        if (poolReserves[j] == reserves[i].underlying) {
          found = true;
          break;
        }
      }

      if (found) {
        console.log('  [PASS]: %s listed in Pool', reserves[i].expectedSymbol);
        passedTests++;
      } else {
        console.log('  [FAIL]: %s NOT listed in Pool', reserves[i].expectedSymbol);
        console.log('    Address: %s', reserves[i].underlying);
        failedTests++;
      }
      totalTests++;
    }

    console.log('');
  }

  // ============================================
  // ASSERTION HELPERS
  // ============================================

  function _checkContractExists(address addr, string memory name) internal {
    uint256 size;
    assembly {
      size := extcodesize(addr)
    }

    if (size == 0) {
      console.log('  [FAIL]: %s has no bytecode', name);
      console.log('    Address: %s', addr);
      failedTests++;
    } else {
      console.log('  [PASS]: %s exists (%s bytes)', name, size);
      passedTests++;
    }
    totalTests++;
  }

  function _assertEqual(address actual, address expected, string memory name) internal {
    if (actual != expected) {
      console.log('  [FAIL]: %s', name);
      console.log('    Expected: %s', expected);
      console.log('    Got: %s', actual);
      failedTests++;
    } else {
      console.log('  [PASS]: %s matches', name);
      passedTests++;
    }
    totalTests++;
  }

  function _getEnvDeployer() internal view returns (address) {
    try vm.envUint('PRIVATE_KEY') returns (uint256 deployerPrivateKey) {
      return vm.addr(deployerPrivateKey);
    } catch {
      return address(0);
    }
  }

  function _printSummary() internal view {
    console.log('========================================');
    console.log('Pre-Deployment Summary');
    console.log('========================================');
    console.log('Total Tests: %s', totalTests);
    console.log('Passed: %s', passedTests);
    console.log('Failed: %s', failedTests);
    console.log('');

    if (failedTests == 0) {
      console.log('[SUCCESS] All pre-deployment checks passed!');
    } else {
      console.log('[FAILED] Pre-deployment checks failed!');
    }
    console.log('========================================');
    console.log('');
  }
}
