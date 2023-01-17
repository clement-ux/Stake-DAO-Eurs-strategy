// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.17;

interface IBooster {
    function depositAll(uint256 _pid, bool _stake) external returns (bool);
}
