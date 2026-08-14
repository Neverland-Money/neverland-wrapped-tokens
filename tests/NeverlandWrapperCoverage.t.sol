// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'forge-std/Test.sol';

import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';

import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {NeverlandMonadMainnet} from '../src/NeverlandAddressBook.sol';

/**
 * @title NeverlandWrapperCoverageTest
 * @notice Guards the wrapper set against drift with the live Neverland pool.
 *
 *         Listing a reserve happens in neverland-pool-operations; wrapping it happens here. Nothing
 *         previously connected the two, so a reserve could go live with no static wrapper and stay
 *         that way unnoticed — which is exactly how cbBTC and XAUt0 ended up unwrapped. These tests
 *         read the live reserve list and fail when a reserve has no wrapper, and pin the
 *         CREATE2-deterministic addresses the address book claims for not-yet-deployed wrappers.
 *
 *         The fork tests are skipped when RPC_MONAD is unset so the suite still runs offline and in
 *         CI without a Monad endpoint. The address-book invariants below need no fork and always
 *         run.
 */
contract NeverlandWrapperCoverageTest is Test {
  uint256 internal constant MONAD_CHAIN_ID = 143;

  StaticATokenFactory internal factory;
  bool internal forked;

  function setUp() public {
    string memory rpc = vm.envOr('RPC_MONAD', string(''));
    if (bytes(rpc).length == 0) {
      return;
    }

    // An unset RPC_MONAD is a legitimate skip: CI has no Monad endpoint. An endpoint pointing at
    // the wrong chain is operator error, and skipping it would hide the coverage regression this
    // file exists to catch behind a green suite. Those two cases end differently on purpose.
    vm.createSelectFork(rpc);
    require(block.chainid == MONAD_CHAIN_ID, 'RPC_MONAD_WRONG_CHAIN');

    factory = StaticATokenFactory(NeverlandMonadMainnet.STATIC_A_TOKEN_FACTORY);
    forked = true;
  }

  /*//////////////////////////////////////////////////////////////
                      LIVE COVERAGE (FORK)
  //////////////////////////////////////////////////////////////*/

  /// @dev Every reserve listed on the Pool must have a static wrapper registered in the factory.
  function test_everyPoolReserveHasAWrapper() public {
    _requireFork();

    address[] memory reserves = IPool(NeverlandMonadMainnet.POOL).getReservesList();
    assertGt(reserves.length, 0, 'pool has no reserves');

    for (uint256 i = 0; i < reserves.length; i++) {
      address wrapper = factory.getStaticAToken(reserves[i]);
      assertTrue(
        wrapper != address(0),
        string.concat(
          'pool reserve ',
          IERC20Metadata(reserves[i]).symbol(),
          ' (',
          vm.toString(reserves[i]),
          ') has no static wrapper - run DeployAdditionalStaticTokens'
        )
      );
    }
  }

  /// @dev The factory must not register a wrapper this repo has never heard of.
  function test_factoryRegistryIsCoveredByAddressBook() public {
    _requireFork();

    address[] memory registered = factory.getStaticATokens();
    address[] memory known = _addressBookWrappers();
    assertGt(registered.length, 0, 'factory has no wrappers');

    for (uint256 i = 0; i < registered.length; i++) {
      assertTrue(
        _contains(known, registered[i]),
        string.concat(
          'factory wrapper ',
          vm.toString(registered[i]),
          ' is missing from NeverlandAddressBook'
        )
      );
    }
  }

  /// @dev Address-book wrappers that are already deployed must be the ones the factory registered.
  function test_deployedAddressBookWrappersMatchFactory() public {
    _requireFork();

    address[] memory underlyings = _addressBookUnderlyings();
    address[] memory wrappers = _addressBookWrappers();

    for (uint256 i = 0; i < underlyings.length; i++) {
      address registered = factory.getStaticAToken(underlyings[i]);
      if (registered == address(0)) {
        continue; // not deployed yet; covered by the determinism test below
      }

      assertEq(registered, wrappers[i], 'address book wrapper does not match factory registry');
      assertEq(
        StaticATokenLM(wrappers[i]).asset(),
        underlyings[i],
        'wrapper is not backed by the underlying the address book pairs it with'
      );
    }
  }

  /**
   * @dev A wrapper address is fixed by CREATE2 before deployment, so a pinned constant is checkable
   *      whether or not the wrapper exists yet. For a deployed wrapper this pins the address against
   *      the live registry; for one still pending it recomputes the address through the live proxy
   *      factory, catching a factory implementation, proxy admin or token naming change that would
   *      otherwise only surface after broadcasting.
   */
  function test_wrapperAddressPinsMatchChain() public {
    _requireFork();

    address[] memory underlyings = _addressBookUnderlyings();
    address[] memory nTokens = _addressBookNTokens();
    address[] memory wrappers = _addressBookWrappers();

    for (uint256 i = 0; i < underlyings.length; i++) {
      _assertWrapperPin(underlyings[i], nTokens[i], wrappers[i]);
    }
  }

  function _assertWrapperPin(address underlying, address nToken, address expected) internal {
    assertEq(
      IPool(NeverlandMonadMainnet.POOL).getReserveData(underlying).aTokenAddress,
      nToken,
      'address book nToken does not match the pool reserve'
    );

    address registered = factory.getStaticAToken(underlying);
    if (registered != address(0)) {
      // Already deployed: the pin must match what actually exists.
      assertEq(registered, expected, 'deployed wrapper does not match the pinned address');
      return;
    }

    // Not deployed: rebuild the exact initialize calldata StaticATokenFactory would use and predict
    // the CREATE2 address through the live proxy factory.
    bytes memory initData = abi.encodeWithSelector(
      StaticATokenLM.initialize.selector,
      nToken,
      string.concat('Wrapped Neverland ', IERC20Metadata(underlying).symbol()),
      string.concat('w', IERC20Metadata(nToken).symbol())
    );

    // Every input is read off the live factory, so nothing here is anchored on the same address
    // book constants the assertion is meant to police.
    address predicted = ITransparentProxyFactory(address(factory.TRANSPARENT_PROXY_FACTORY()))
      .predictCreateDeterministic(
        factory.STATIC_A_TOKEN_IMPL(),
        factory.ADMIN(),
        initData,
        bytes32(uint256(uint160(underlying)))
      );

    assertEq(predicted, expected, 'pinned wrapper address is stale - re-derive it');
  }

  /**
   * @dev Every wrapper must carry the metadata StaticATokenFactory's naming rule produces: the name
   *      from the UNDERLYING symbol, the symbol from the nTOKEN symbol. Integrators and the README
   *      table both depend on this, and getting the two symbol sources backwards would still deploy
   *      cleanly.
   *
   *      A wrapper that does not exist yet is created against the fork first, so this is a real
   *      pre-broadcast proof rather than a check that quietly does nothing while a reserve is
   *      unwrapped. Creating on the fork also removes the last assumption the pin test makes — that
   *      the initialize calldata was transcribed from the factory correctly — because here the real
   *      factory builds it.
   */
  function test_everyWrapperHasFactoryRuleMetadata() public {
    _requireFork();

    address[] memory underlyings = _addressBookUnderlyings();
    address[] memory nTokens = _addressBookNTokens();
    address[] memory wrappers = _addressBookWrappers();

    for (uint256 i = 0; i < underlyings.length; i++) {
      address wrapper = factory.getStaticAToken(underlyings[i]);

      if (wrapper == address(0)) {
        address[] memory toCreate = new address[](1);
        toCreate[0] = underlyings[i];
        wrapper = factory.createStaticATokens(toCreate)[0];
        assertEq(wrapper, wrappers[i], 'created wrapper does not match the pinned address');
      }

      _assertWrapperMetadata(wrapper, underlyings[i], nTokens[i]);
    }

    // With any gap filled on the fork, the coverage invariant the suite guards must now hold.
    address[] memory reserves = IPool(NeverlandMonadMainnet.POOL).getReservesList();
    for (uint256 i = 0; i < reserves.length; i++) {
      assertTrue(factory.getStaticAToken(reserves[i]) != address(0), 'reserve still unwrapped');
    }
  }

  function _assertWrapperMetadata(address wrapper, address underlying, address nToken) internal {
    StaticATokenLM w = StaticATokenLM(wrapper);

    assertEq(w.asset(), underlying, 'wrapper asset');
    assertEq(address(w.aToken()), nToken, 'wrapper aToken');
    assertEq(address(w.POOL()), NeverlandMonadMainnet.POOL, 'wrapper pool');
    assertEq(
      address(w.INCENTIVES_CONTROLLER()),
      NeverlandMonadMainnet.DUST_REWARDS_CONTROLLER,
      'wrapper rewards controller'
    );
    assertEq(w.decimals(), IERC20Metadata(underlying).decimals(), 'wrapper decimals');
    assertEq(
      w.name(),
      string.concat('Wrapped Neverland ', IERC20Metadata(underlying).symbol()),
      'wrapper name'
    );
    assertEq(w.symbol(), string.concat('w', IERC20Metadata(nToken).symbol()), 'wrapper symbol');
    assertEq(
      w.REWARD_RESCUE_ADMIN(),
      NeverlandMonadMainnet.PROXY_ADMIN_OWNER,
      'wrapper rescue admin'
    );
  }

  /*//////////////////////////////////////////////////////////////
                    ADDRESS BOOK INVARIANTS (LOCAL)
  //////////////////////////////////////////////////////////////*/

  /// @dev Runs without a fork so a copy-paste slip in the address book fails everywhere, not only
  ///      where a Monad endpoint happens to be configured.
  function test_addressBookEntriesAreDistinctAndNonZero() public pure {
    address[] memory underlyings = _addressBookUnderlyings();
    address[] memory nTokens = _addressBookNTokens();
    address[] memory wrappers = _addressBookWrappers();

    require(underlyings.length == nTokens.length, 'UNDERLYING_NTOKEN_LENGTH');
    require(underlyings.length == wrappers.length, 'UNDERLYING_WRAPPER_LENGTH');

    _assertDistinctAndNonZero(underlyings);
    _assertDistinctAndNonZero(nTokens);
    _assertDistinctAndNonZero(wrappers);
  }

  function _assertDistinctAndNonZero(address[] memory entries) internal pure {
    for (uint256 i = 0; i < entries.length; i++) {
      require(entries[i] != address(0), 'ADDRESS_BOOK_ZERO_ENTRY');
      for (uint256 j = i + 1; j < entries.length; j++) {
        require(entries[i] != entries[j], 'ADDRESS_BOOK_DUPLICATE_ENTRY');
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                              HELPERS
  //////////////////////////////////////////////////////////////*/

  function _requireFork() internal {
    if (!forked) {
      // No Monad endpoint configured; the live checks cannot run.
      vm.skip(true);
    }
  }

  function _contains(address[] memory haystack, address needle) internal pure returns (bool) {
    for (uint256 i = 0; i < haystack.length; i++) {
      if (haystack[i] == needle) {
        return true;
      }
    }
    return false;
  }

  /// @dev Index-aligned with _addressBookNTokens and _addressBookWrappers.
  function _addressBookUnderlyings() internal pure returns (address[] memory entries) {
    entries = new address[](13);
    entries[0] = NeverlandMonadMainnet.WMON;
    entries[1] = NeverlandMonadMainnet.USDC;
    entries[2] = NeverlandMonadMainnet.USDT0;
    entries[3] = NeverlandMonadMainnet.WBTC;
    entries[4] = NeverlandMonadMainnet.WETH;
    entries[5] = NeverlandMonadMainnet.SMON;
    entries[6] = NeverlandMonadMainnet.SHMON;
    entries[7] = NeverlandMonadMainnet.GMON;
    entries[8] = NeverlandMonadMainnet.AUSD;
    entries[9] = NeverlandMonadMainnet.EARNAUSD;
    entries[10] = NeverlandMonadMainnet.LOAZND;
    entries[11] = NeverlandMonadMainnet.CBBTC;
    entries[12] = NeverlandMonadMainnet.XAUT0;
  }

  function _addressBookNTokens() internal pure returns (address[] memory entries) {
    entries = new address[](13);
    entries[0] = NeverlandMonadMainnet.N_WMON;
    entries[1] = NeverlandMonadMainnet.N_USDC;
    entries[2] = NeverlandMonadMainnet.N_USDT0;
    entries[3] = NeverlandMonadMainnet.N_WBTC;
    entries[4] = NeverlandMonadMainnet.N_WETH;
    entries[5] = NeverlandMonadMainnet.N_SMON;
    entries[6] = NeverlandMonadMainnet.N_SHMON;
    entries[7] = NeverlandMonadMainnet.N_GMON;
    entries[8] = NeverlandMonadMainnet.N_AUSD;
    entries[9] = NeverlandMonadMainnet.N_EARNAUSD;
    entries[10] = NeverlandMonadMainnet.N_LOAZND;
    entries[11] = NeverlandMonadMainnet.N_CBBTC;
    entries[12] = NeverlandMonadMainnet.N_XAUT0;
  }

  function _addressBookWrappers() internal pure returns (address[] memory entries) {
    entries = new address[](13);
    entries[0] = NeverlandMonadMainnet.STATN_WMON;
    entries[1] = NeverlandMonadMainnet.STATN_USDC;
    entries[2] = NeverlandMonadMainnet.STATN_USDT0;
    entries[3] = NeverlandMonadMainnet.STATN_WBTC;
    entries[4] = NeverlandMonadMainnet.STATN_WETH;
    entries[5] = NeverlandMonadMainnet.STATN_SMON;
    entries[6] = NeverlandMonadMainnet.STATN_SHMON;
    entries[7] = NeverlandMonadMainnet.STATN_GMON;
    entries[8] = NeverlandMonadMainnet.STATN_AUSD;
    entries[9] = NeverlandMonadMainnet.STATN_EARNAUSD;
    entries[10] = NeverlandMonadMainnet.STATN_LOAZND;
    entries[11] = NeverlandMonadMainnet.STATN_CBBTC;
    entries[12] = NeverlandMonadMainnet.STATN_XAUT0;
  }
}
