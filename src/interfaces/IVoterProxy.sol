// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IVoterProxy {
    function withdraw(address _gauge, address _token, uint256 _amount) external returns (uint256);

    function balanceOf(address _gauge) external view returns (uint256);

    function withdrawAll(address _gauge, address _token) external returns (uint256);

    function deposit(address _gauge, address _token) external;

    function harvest(address _gauge, bool _snxRewards) external;

    function lock() external;
}
