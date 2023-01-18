// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

// forge install OpenZeppelin/openzeppelin-contracts@v4.8.1
import "openzeppelin/contracts/token/ERC20/IERC20.sol";
import "openzeppelin/contracts/utils/math/SafeMath.sol";
import "openzeppelin/contracts/utils/Address.sol";
import "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "src/interfaces/IBooster.sol";
import "src/interfaces/IBaseRewardPool.sol";
import "src/interfaces/IController.sol";
import "src/interfaces/IVoterProxy.sol";
import "src/interfaces/Sushi.sol";
import "src/interfaces/ICurveFi.sol";
import "src/interfaces/ISwapRouter.sol";

contract StrategyEursConvex {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // eursCRV
    address public constant want = address(0x194eBd173F6cDacE046C53eACcE9B953F28411d1);

    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);

    address public constant cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    address public constant eurs = address(0xdB25f211AB05b1c97D595516F45794528a807ad8);

    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public constant usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address public constant voter = address(0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6);

    address public constant sushiRouter = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    address public constant curve = address(0x0Ce6a5fF5217e38315f87032CF90686C96627CAA);

    address public constant quoter = address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    address public constant uniswapRouterAddress = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public constant LIFI_DIAMOND = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    ISwapRouter public constant uniswapRouter = ISwapRouter(uniswapRouterAddress);

    uint256 public keepCRV = 0;
    uint256 public performanceFee = 1500;
    uint256 public withdrawalFee = 50;
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public proxy;

    address public governance;
    address public controller;
    address public strategist;

    uint256 public earned; // lifetime strategy earnings denominated in `want` token

    // convex booster
    address public booster;
    address public baseRewardPool;

    error SWAP_FAILED();

    event Harvested(uint256 wantEarned, uint256 lifetimeEarned);

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyController() {
        require(msg.sender == controller, "!controller");
        _;
    }

    constructor(address _controller, address _proxy) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
        proxy = _proxy;
        booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
        baseRewardPool = address(0xcB8F69E0064d8cdD29cbEb45A14cf771D904BcD3);
    }

    function getName() external pure returns (string memory) {
        return "StrategyEursConvex";
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == governance || msg.sender == strategist, "!authorized");
        strategist = _strategist;
    }

    function setKeepCRV(uint256 _keepCRV) external onlyGovernance {
        keepCRV = _keepCRV;
    }

    function setWithdrawalFee(uint256 _withdrawalFee) external onlyGovernance {
        withdrawalFee = _withdrawalFee;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyGovernance {
        performanceFee = _performanceFee;
    }

    function setProxy(address _proxy) external onlyGovernance {
        proxy = _proxy;
    }

    function deposit() public {
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).safeApprove(booster, 0);
        IERC20(want).safeApprove(booster, _want);
        IBooster(booster).depositAll(22, true);
    }

    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external onlyController returns (uint256 balance) {
        require(want != address(_asset), "want");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint256 _amount) external onlyController {
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }

        uint256 _fee = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);

        IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 wantBefore = IERC20(want).balanceOf(address(this));
        IBaseRewardPool(baseRewardPool).withdrawAndUnwrap(_amount, false);
        uint256 wantAfter = IERC20(want).balanceOf(address(this));
        return wantAfter.sub(wantBefore);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external onlyController returns (uint256 balance) {
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }

    function _withdrawAll() internal {
        IBaseRewardPool(baseRewardPool).withdrawAllAndUnwrap(false);
    }

    function harvest(bytes calldata swapDataCRV, bytes calldata swapDataCVX, uint256 minAmountEURS) public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        IBaseRewardPool(baseRewardPool).getReward(address(this), true);

        uint256 _crv = IERC20(crv).balanceOf(address(this));
        uint256 _cvx = IERC20(cvx).balanceOf(address(this));

        if (_crv > 0) {
            uint256 _keepCRV = _crv.mul(keepCRV).div(FEE_DENOMINATOR);
            IERC20(crv).safeTransfer(voter, _keepCRV);
            _crv = _crv.sub(_keepCRV);

            IERC20(crv).safeApprove(LIFI_DIAMOND, 0);
            IERC20(crv).safeApprove(LIFI_DIAMOND, _crv);

            (bool success,) = LIFI_DIAMOND.call(swapDataCRV);
            if (!success) revert SWAP_FAILED();
        }

        if (_cvx > 0) {
            IERC20(cvx).safeApprove(LIFI_DIAMOND, 0);
            IERC20(cvx).safeApprove(LIFI_DIAMOND, _cvx);

            (bool success,) = LIFI_DIAMOND.call(swapDataCVX);
            if (!success) revert SWAP_FAILED();
        }

        uint256 _eurs = IERC20(eurs).balanceOf(address(this));
        console.log("_eurs: ", _eurs);

        if (_eurs > 0) {
            IERC20(eurs).safeApprove(curve, 0);
            IERC20(eurs).safeApprove(curve, _eurs);

            ICurveFi(curve).add_liquidity([_eurs, 0], minAmountEURS);
        }

        uint256 _want = IERC20(want).balanceOf(address(this));

        if (_want > 0) {
            uint256 _fee = _want.mul(performanceFee).div(FEE_DENOMINATOR);
            IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
            deposit();
        }

        IVoterProxy(proxy).lock();
        earned = earned.add(_want);
        emit Harvested(_want, earned);
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        return IBaseRewardPool(baseRewardPool).balanceOf(address(this));
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function setController(address _controller) external onlyGovernance {
        controller = _controller;
    }
}
