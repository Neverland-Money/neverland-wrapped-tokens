// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import 'forge-std/Script.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {NeverlandMonadMainnet} from '../src/NeverlandAddressBook.sol';

/**
 * @title DeployAdditionalStaticTokens
 * @notice Script to deploy static tokens for newly added reserves
 * @dev Use this when you add new reserves to Neverland and want to create their static wrappers
 *      without redeploying the entire factory infrastructure
 *
 * Usage:
 *   1. Add new reserve addresses to NeverlandAddressBook.sol
 *   2. Update FACTORY_ADDRESS below with your deployed factory
 *   3. Update NEW_RESERVES array with addresses of new reserves
 *   4. Run: forge script scripts/DeployAdditionalStaticTokens.s.sol:DeployAdditionalStaticTokens \
 *           --rpc-url monad --broadcast -vvv
 */
contract DeployAdditionalStaticTokens is Script {
  // UPDATE THIS: Address of your deployed StaticATokenFactory
  address constant FACTORY_ADDRESS = address(0); // UPDATE AFTER INITIAL DEPLOYMENT

  function getNewReserves() internal pure returns (address[] memory) {
    // UPDATE THIS: Add new reserve addresses here
    address[] memory reserves = new address[](0);

    // Example for future reserves:
    // reserves = new address[](2);
    // reserves[0] = 0x...; // New reserve 1
    // reserves[1] = 0x...; // New reserve 2

    return reserves;
  }

  function run() external {
    require(FACTORY_ADDRESS != address(0), 'Update FACTORY_ADDRESS first');

    address[] memory newReserves = getNewReserves();
    require(newReserves.length > 0, 'No new reserves specified');

    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployer = vm.addr(deployerPrivateKey);

    console.log('\n========================================');
    console.log('Deploy Additional Static Tokens');
    console.log('========================================');
    console.log('Deployer:', deployer);
    console.log('Factory:', FACTORY_ADDRESS);
    console.log('Reserves to check:', newReserves.length);
    console.log('');

    StaticATokenFactory factory = StaticATokenFactory(FACTORY_ADDRESS);

    // Filter out reserves that already have static tokens
    console.log('=== Checking Existing Static Tokens ===');
    address[] memory reservesToDeploy = new address[](newReserves.length);
    uint256 deployCount = 0;

    for (uint256 i = 0; i < newReserves.length; i++) {
      address existingStaticToken = factory.getStaticAToken(newReserves[i]);

      if (existingStaticToken == address(0)) {
        console.log('[NEW] Reserve %s - will deploy', newReserves[i]);
        reservesToDeploy[deployCount] = newReserves[i];
        deployCount++;
      } else {
        console.log(
          '[SKIP] Reserve %s - already has static token at %s',
          newReserves[i],
          existingStaticToken
        );
      }
    }

    if (deployCount == 0) {
      console.log('');
      console.log('========================================');
      console.log('[INFO] All reserves already have static tokens!');
      console.log('========================================');
      return;
    }

    // Resize array to actual deployment count
    address[] memory filteredReserves = new address[](deployCount);
    for (uint256 i = 0; i < deployCount; i++) {
      filteredReserves[i] = reservesToDeploy[i];
    }

    console.log('');
    console.log('Deploying %s new static token(s)...', deployCount);

    vm.startBroadcast(deployerPrivateKey);

    // Create static tokens only for new reserves
    address[] memory newStaticTokens = factory.createStaticATokens(filteredReserves);

    vm.stopBroadcast();

    console.log('\n=== New Static Tokens Deployed ===');
    for (uint256 i = 0; i < filteredReserves.length; i++) {
      console.log('Reserve:', filteredReserves[i]);
      console.log('  Static Token:', newStaticTokens[i]);
    }

    console.log('\n========================================');
    console.log('[SUCCESS] %s static token(s) deployed!', deployCount);
    console.log('========================================');
    console.log('\nNext steps:');
    console.log('1. Update NeverlandAddressBook.sol with new static token addresses');
    console.log('2. Run VerifyDeployment.s.sol to validate');
    console.log('3. Share new addresses with Balancer team');
    console.log('');
  }
}
