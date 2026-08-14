// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title NeverlandAddressBook
 * @notice Central registry of Neverland's deployed contracts on Monad
 * @dev Update this file when deploying to new environments or adding contracts
 */
library NeverlandMonadMainnet {
  // ============================================
  // CORE PROTOCOL
  // ============================================

  address internal constant POOL = 0x80F00661b13CC5F6ccd3885bE7b4C9c67545D585;
  address internal constant POOL_ADDRESSES_PROVIDER = 0x49D75170F55C964dfdd6726c74fdEDEe75553A0f;
  address internal constant DUST_REWARDS_CONTROLLER = 0x57ea245cCbFAb074baBb9d01d1F0c60525E52cec;

  // ============================================
  // DEPLOYER
  // ============================================

  address internal constant DEPLOYER = 0x0000B06460777398083CB501793a4d6393900000;

  // ============================================
  // RESERVE ASSETS
  // ============================================

  address internal constant WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
  address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
  address internal constant USDT0 = 0xe7cd86e13AC4309349F30B3435a9d337750fC82D;
  address internal constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
  address internal constant WETH = 0xEE8c0E9f1BFFb4Eb878d8f15f368A02a35481242;
  address internal constant SMON = 0xA3227C5969757783154C60bF0bC1944180ed81B9;
  address internal constant SHMON = 0x1B68626dCa36c7fE922fD2d55E4f631d962dE19c;
  address internal constant GMON = 0x8498312A6B3CbD158bf0c93AbdCF29E6e4F55081;
  address internal constant AUSD = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
  address internal constant EARNAUSD = 0x103222f020e98Bba0AD9809A011FDF8e6F067496;
  address internal constant LOAZND = 0x9c82eB49B51F7Dc61e22Ff347931CA32aDc6cd90;
  address internal constant CBBTC = 0xd18B7EC58Cdf4876f6AFebd3Ed1730e4Ce10414b;
  address internal constant XAUT0 = 0x01bFF41798a0BcF287b996046Ca68b395DbC1071;

  // ============================================
  // nTOKENS (aTokens)
  // ============================================

  address internal constant N_WMON = 0xD0fd2Cf7F6CEff4F96B1161F5E995D5843326154;
  address internal constant N_USDC = 0x38648958836eA88b368b4ac23b86Ad44B0fe7508;
  address internal constant N_USDT0 = 0x39F901c32b2E0d25AE8DEaa1ee115C748f8f6bDf;
  address internal constant N_WBTC = 0x34c43684293963c546b0aB6841008A4d3393B9ab;
  address internal constant N_WETH = 0x31f63Ae5a96566b93477191778606BeBDC4CA66f;
  address internal constant N_SMON = 0xdFC14d336aea9E49113b1356333FD374e646Bf85;
  address internal constant N_SHMON = 0xC64d73Bb8748C6fA7487ace2D0d945B6fBb2EcDe;
  address internal constant N_GMON = 0x7f81779736968836582D31D36274Ed82053aD1AE;
  address internal constant N_AUSD = 0x784999fc2Dd132a41D1Cc0F1aE9805854BaD1f2D;
  address internal constant N_EARNAUSD = 0xaCaaA891b30E13D024AB67b6EcA9c2EcBD8cf52b;
  address internal constant N_LOAZND = 0x293e2f01a38Fe690Eb8E570AB952b24b225113a7;
  address internal constant N_CBBTC = 0xcc7f5F78Bedfc65c2fDD93C7537832eEa1324774;
  address internal constant N_XAUT0 = 0x3351683194670680Edd1700Bfbe146403684AEdf;

  // ============================================
  // STATIC ATOKEN INFRASTRUCTURE
  // ============================================
  // Deployed infrastructure

  address internal constant PROXY_ADMIN = 0x0cBe49645BCC84eD90A6aA4D93dfEb2Cc836F721;
  address internal constant PROXY_ADMIN_OWNER = 0x3e4749D9Df7EC5ecd9184c301592bAc058a6F82f;
  address internal constant TRANSPARENT_PROXY_FACTORY = 0x8A93f9d1aEc306727cb70b3F500651C6a0Ccec0F;
  address internal constant STATIC_A_TOKEN_IMPL = 0xD75D6Bf28519aCD719ae59Cbc47D9af0a0792af1;
  address internal constant STATIC_A_TOKEN_FACTORY_IMPL =
    0x6D48BeEa61aA165a54f0DD937919204F1A59ED1B;
  address internal constant STATIC_A_TOKEN_FACTORY = 0x81148e8e1D9910080317E11c9f178559Ba23Bc80;

  // ============================================
  // STATIC ATOKENS
  // ============================================
  // Wrapped static aTokens (wn*)

  address internal constant STATN_WMON = 0xdB39A9D4a1f1b4e93A5684d602207628aD60613C;
  address internal constant STATN_USDC = 0x8d5c2Df3Eef09088Fcccf3376D8EcD0Dd505f642;
  address internal constant STATN_USDT0 = 0x4e8aaecCE10ad9394e96fE5f2bd4e587A7B04298;
  address internal constant STATN_WBTC = 0x8959f4E6ED1f4567a464959793d5f8f6f33C1C8B;
  address internal constant STATN_WETH = 0xB3b850ac62B89fe9f4eFB652b516108a8aEb8848;
  address internal constant STATN_SMON = 0x08139339dd9A480CEB84D9C7CcE48BE436dB20b3;
  address internal constant STATN_SHMON = 0x5e073494678fB7FA4a05bB17d45941Dd9Dc469c1;
  address internal constant STATN_GMON = 0x29D2075E5151B1A6863bDC40EA86bD5e8aFd1705;
  address internal constant STATN_AUSD = 0x82c370ba90E38ef6Acd8b1b078d34fD86FC6bAC9;
  address internal constant STATN_EARNAUSD = 0xD45D54ad7Ae6D5dEdb0De7B283Fe0b4e2ba40217;
  address internal constant STATN_LOAZND = 0xD786F7569C39A9F64E6A54Eb77db21364E90F279;
  address internal constant STATN_CBBTC = 0x98a297e6424787E57Af119949d7E00b721F832BB;
  address internal constant STATN_XAUT0 = 0x22139A346b6312EB0A9812C67CfCe4A694676d59;

  // ============================================
  // PINNED WRAPPER SET
  // ============================================

  /**
   * @notice Every static wrapper this repo knows about, whether already deployed or pinned ahead of
   *         its deployment.
   * @dev Scripts that act on the live factory registry check it against this set, so a wrapper
   *      created outside this repo is rejected rather than silently upgraded. Kept here rather than
   *      in each script so the set cannot drift between the export path and the fork proofs.
   */
  function staticATokens() internal pure returns (address[] memory wrappers) {
    wrappers = new address[](13);
    wrappers[0] = STATN_WMON;
    wrappers[1] = STATN_USDC;
    wrappers[2] = STATN_USDT0;
    wrappers[3] = STATN_WBTC;
    wrappers[4] = STATN_WETH;
    wrappers[5] = STATN_SMON;
    wrappers[6] = STATN_SHMON;
    wrappers[7] = STATN_GMON;
    wrappers[8] = STATN_AUSD;
    wrappers[9] = STATN_EARNAUSD;
    wrappers[10] = STATN_LOAZND;
    wrappers[11] = STATN_CBBTC;
    wrappers[12] = STATN_XAUT0;
  }

  /// @notice Whether `wrapper` is one of the wrappers pinned in this address book.
  function isPinnedStaticAToken(address wrapper) internal pure returns (bool) {
    address[] memory wrappers = staticATokens();
    for (uint256 i = 0; i < wrappers.length; i++) {
      if (wrappers[i] == wrapper) {
        return true;
      }
    }
    return false;
  }
}
