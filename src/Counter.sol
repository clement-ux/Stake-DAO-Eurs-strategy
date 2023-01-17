// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.17;

contract Counter {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}