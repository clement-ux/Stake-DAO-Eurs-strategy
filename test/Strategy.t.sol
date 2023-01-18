// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "src/Strategy.sol";

contract StrategyTest is Test{
    address internal constant CONTROLLER = 0x29D3782825432255041Db2EAfCB7174f5273f08A;
    address internal constant EURS_LP = 0x194eBd173F6cDacE046C53eACcE9B953F28411d1;
    address internal constant VAULT = 0xCD6997334867728ba14d7922f72c893fcee70e84;
    address internal constant PROXY = 0xF34Ae3C7515511E29d8Afe321E67Bdf97a274f1A;
    address internal constant DEPLOYER = address(0xDE);


    StrategyEursConvex strategy;

    function setUp() public  {
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), 16_432_000));
        
        vm.prank(DEPLOYER);
        strategy = new StrategyEursConvex(CONTROLLER, PROXY);
    }

    function testNothing() public {}
}