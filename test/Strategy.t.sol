// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "src/Strategy.sol";
import "src/Harvestor.sol";

import "src/interfaces/IVault.sol";
import "src/interfaces/IController.sol";
import "src/interfaces/ISwapRouter.sol";
import "src/interfaces/IBaseRewardPool.sol";

import "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StrategyTest is Test {
    address internal constant CONTROLLER = 0x29D3782825432255041Db2EAfCB7174f5273f08A;
    address internal constant EURS_LP = 0x194eBd173F6cDacE046C53eACcE9B953F28411d1;
    address internal constant EURS_POOL = 0x0Ce6a5fF5217e38315f87032CF90686C96627CAA;
    address internal constant VAULT = 0xCD6997334867728ba14d7922f72c893fcee70e84;
    address internal constant OLD_STRATEGY = 0x6e6395cbF07Fe480dEae1076AA7d8A2B65edfC3d;
    address internal constant PROXY = 0xF34Ae3C7515511E29d8Afe321E67Bdf97a274f1A;
    address internal constant BASE_REWARD_POOL = 0xcB8F69E0064d8cdD29cbEb45A14cf771D904BcD3;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant EURS = 0xdB25f211AB05b1c97D595516F45794528a807ad8;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant UNISWAP_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address internal constant DEPLOYER = address(0xDE);

    IVault vault = IVault(VAULT);
    IController controller = IController(CONTROLLER);
    IBaseRewardPool baseRewardPool = IBaseRewardPool(BASE_REWARD_POOL);

    Harvestor harvestor;
    StrategyEursConvex strategy;

    function setUp() public {
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet")));

        vm.startPrank(DEPLOYER);
        strategy = new StrategyEursConvex(CONTROLLER, PROXY);
        harvestor = new Harvestor();
        vm.stopPrank();
    }

    /// @notice Test to replace the old strategy on the controller by the new one
    /// @notice and migrate all the eurs LP from the old strategy to the new one
    /// @notice using the vault.
    function testSwitchStrategy() public {
        uint256 balanceBefore = baseRewardPool.balanceOf(OLD_STRATEGY);

        vm.startPrank(controller.governance());
        controller.approveStrategy(EURS_LP, address(strategy));
        controller.setStrategy(EURS_LP, address(strategy));
        controller.revokeStrategy(EURS_LP, OLD_STRATEGY);
        assertEq(ERC20(EURS_LP).balanceOf(VAULT), balanceBefore);

        vault.earn();
        vm.stopPrank();

        assertApproxEqRel(baseRewardPool.balanceOf(address(strategy)), balanceBefore, 5e16); // due to `available()` on vault
    }

    /// @notice Test to claim CRV and CVX rewards after 2 weeks for the new strategy
    function testClaimRewardOnNewStrat() public {
        testSwitchStrategy();
        skip(2 weeks);

        uint256 balanceBeforeCRV = ERC20(CRV).balanceOf(address(strategy));
        uint256 balanceBeforeCVX = ERC20(CVX).balanceOf(address(strategy));
        baseRewardPool.getReward(address(strategy), false);

        assertGt(ERC20(CRV).balanceOf(address(strategy)), balanceBeforeCRV);
        assertGt(ERC20(CVX).balanceOf(address(strategy)), balanceBeforeCVX);
    }

    /// @notice Test to harvest the strategy. Because the quote only work at the current time
    /// @notice rewards are simulated by dealing CRV and CVX directly to the strategy.
    function testHarvest() public {
        testSwitchStrategy();

        deal(CRV, address(strategy), 1_000 ether);
        deal(CVX, address(strategy), 100 ether);

        uint256 balanceBefore = baseRewardPool.balanceOf(address(strategy));
        (uint256 quoteFromCRV, bytes memory swapDataCRV) = getQuote(CRV, EURS, 1_000 ether, address(strategy));
        (uint256 quoteFromCVX, bytes memory swapDataCVX) = getQuote(CVX, EURS, 100 ether, address(strategy));
        uint256 adjustedQuote = (quoteFromCRV + quoteFromCVX) * 995 / 1000;
        uint256 minAmountEURS = ICurveFi(EURS_POOL).calc_token_amount([adjustedQuote, 0], true);

        vm.prank(address(strategy.strategist()));
        strategy.harvest(swapDataCRV, swapDataCVX, minAmountEURS);

        assertGt(baseRewardPool.balanceOf(address(strategy)), balanceBefore);
    }

    function testHarvestOldStrategy() public {
        uint256 amount0 = 2_000_000e6;
        uint256 amount1 = 2_000_000e2;
        address token0 = USDC;
        address token1 = EURS;
        //int24 tickDai = 887272;
        int24 tickEurs = 147800;
        //uint24 feeDai = 100;
        uint24 feeEurs = 500;

        deal(token0, address(harvestor), 2 * amount0);
        deal(token1, address(harvestor), 2 * amount1);

        // Weird behavior when adding liquidity, this is the event emitted during the add liquidity process :
        // emit IncreaseLiquidity(tokenId: 416027, liquidity: 1235248687, amount0: 1999999998861, amount1: 0)
        harvestor.mintNewPosition(amount0, amount1, token0, token1, tickEurs, feeEurs);

        // Quote call revert with the following error message : "SPL"
        ISwapRouter(UNISWAP_QUOTER).quoteExactInput(abi.encodePacked(token0, uint24(500), token1), 1 ether);
    }

    function getQuote(address srcToken, address dstToken, uint256 amount, address fromAddress)
        internal
        returns (uint256 _quote, bytes memory data)
    {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "test/python/get_quote.py";
        inputs[2] = vm.toString(srcToken);
        inputs[3] = vm.toString(dstToken);
        inputs[4] = vm.toString(amount);
        inputs[5] = vm.toString(fromAddress);

        return abi.decode(vm.ffi(inputs), (uint256, bytes));
    }
}
