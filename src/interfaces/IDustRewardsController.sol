// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title IDustRewardsController
 * @notice Minimal interface for Neverland's DustRewardsController claim function.
 * @dev Used to keep StaticATokenLM compatible with both Dust and Aave controllers.
 */
interface IDustRewardsController {
  function claimRewards(
    address[] calldata assets,
    uint256 amount,
    address to,
    address reward,
    uint256 lockTime,
    uint256 tokenId
  ) external returns (uint256);
}
