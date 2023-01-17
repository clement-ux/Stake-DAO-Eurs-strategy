// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.17;

interface IBaseRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    function withdrawAllAndUnwrap(bool claim) external;

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function balanceOf(address) external view returns (uint256);
}
