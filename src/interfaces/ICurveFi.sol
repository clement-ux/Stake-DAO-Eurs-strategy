// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface ICurveFi {
    function add_liquidity(uint256[2] calldata, uint256) external;

    function calc_token_amount(uint256[2] calldata, bool) external returns (uint256);
}
