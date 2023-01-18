// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IBooster {
    function depositAll(uint256 _pid, bool _stake) external returns (bool);
}
