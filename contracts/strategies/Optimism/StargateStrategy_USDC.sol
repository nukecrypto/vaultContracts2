// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import {BasicStrategy} from "../BasicStrategy.sol";
import "../../interfaces/Stargate.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ISwapRouter03, IV3SwapRouter} from "../../interfaces/Uniswap.sol";
// import "hardhat/console.sol"; // TODO: Remove before deploy

/**
 * @title StargateStrategy_USDC
 * @dev Defined strategy(I.e curve 3pool) that inherits structure and functionality from BasicStrategy
 */
contract StargateStrategy_USDC is BasicStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address private _stakeDeposit =
        address(0x4DeA9e918c6289a52cd469cAC652727B7b412Cd2);

    address private _router =
        address(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);

    address private _rewardToken =
        address(0x4200000000000000000000000000000000000042); // OP Token

    address private _usdcToken =
        address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    uint256 private pid = 0;

    int128 private _tokenIndex = 0;
    uint256 private _slippageAllowed = 10000000; // 10000000 = 1%

    constructor(
        address _vault,
        address _wantToken,
        address _poolInvestToken
    ) BasicStrategy(_vault, _wantToken, _poolInvestToken) {}

    /// @return name of the strategy
    function getName() external pure override returns (string memory) {
        return "StargateStrategy_USDC";
    }

    /// @dev pre approves max
    function doApprovals() public {
        IERC20(want()).safeApprove(_stakeDeposit, type(uint256).max);
        IERC20(_rewardToken).safeApprove(univ3Router2, type(uint256).max);
        IERC20(_usdcToken).safeApprove(_router, type(uint256).max);
    }

    /// @notice gives an estimate of tokens invested
    function balanceOfPool() public view override returns (uint256) {
        (uint256 amount, ) = IStargateFarm(_stakeDeposit).userInfo(pid,address(this));
        return amount;
    }

    function depositFromVault() public onlyVault {
        _deposit();
    }

    /// @notice invests available funds
    function deposit() public override onlyMinion {
        _deposit();
    }

    function _deposit() internal {
        uint256 availableFundsToDeposit = getAvailableFunds();
        require(availableFundsToDeposit > 0, "No funds available");
        IStargateFarm(_stakeDeposit).deposit(pid, availableFundsToDeposit);
    }

    function checkPendingReward() public view returns (uint256) {
        return IStargateFarm(_stakeDeposit).pendingEmissionToken(pid, address(this));
    }

    /// @notice withdraws all from pool to strategy where the funds can safetly be withdrawn by it's owners
    /// @dev this is only to be allowed by governance and should only be used in the event of a strategy or pool not functioning correctly/getting discontinued etc
    function withdrawAll() public override onlyGovernance {
        IStargateFarm(_stakeDeposit).withdraw(pid, balanceOfPool());
    }

    /// @notice withdraws a certain amount from the pool
    /// @dev can only be called from inside the contract through the withdraw function which is protected by only vault modifier
    function _withdrawAmount(uint256 _amount)
        internal
        override
        onlyVault
        returns (uint256)
    {
        uint256 beforeWithdraw = getAvailableFunds();

        uint256 balanceOfPoolAmount = balanceOfPool();

        if (_amount > balanceOfPoolAmount) {
            _amount = balanceOfPoolAmount;
        }

        IStargateFarm(_stakeDeposit).withdraw(pid, _amount);

        uint256 afterWithdraw = getAvailableFunds();

        return afterWithdraw.sub(beforeWithdraw);
    }

    /// @notice call to withdraw funds to vault
    function withdraw(uint256 _amount)
        external
        override
        onlyVault
        returns (uint256)
    {
        uint256 availableFunds = getAvailableFunds();

        if (availableFunds >= _amount) {
            IERC20(wantToken).safeTransfer(__vault, _amount);
            return _amount;
        }

        uint256 amountToWithdrawFromGauge = _amount.sub(availableFunds);

        uint256 amountThatWasWithdrawn = _withdrawAmount(amountToWithdrawFromGauge);

        availableFunds = getAvailableFunds();

        if(availableFunds < _amount){
            _amount = availableFunds;
        }

        IERC20(wantToken).safeTransfer(__vault, _amount);

        return _amount;
    }

    function harvest() public onlyMinion {
        IStargateFarm(_stakeDeposit).deposit(pid, 0);
    }

    /// @notice harvests rewards, sells them for want and reinvests them
    function harvestAndReinvest() public override onlyMinion {
        harvest();
        swapReward();
        addLiquidity();
        _deposit();
    }

    function swapReward() public onlyMinion {
        uint256 rewardAmount = IERC20(_rewardToken).balanceOf(
            address(this)
        );

        require(rewardAmount > 0, "No Rewards");

        //Swap
        uint256 amountOut = ISwapRouter03(univ3Router2).exactInput(
            IV3SwapRouter.ExactInputParams({
        path: abi.encodePacked(
                _rewardToken,
                _poolFee,
                ISwapRouter03(univ3Router2).WETH9(),
                _poolFee,
                _usdcToken
            ),
        recipient: address(this),
        amountIn: rewardAmount,
        amountOutMinimum: 0
        })
        );

        if (performanceFee > 0 && amountOut > 0) {
            uint256 _fee = calculateFee(amountOut, performanceFee);
            IERC20(_usdcToken).safeTransfer(feeAddress, _fee);
        }
    }

    function addLiquidity() public onlyMinion {
        uint256 allUSDC = IERC20(_usdcToken).balanceOf(address(this));
        //convert to LP token
        IStargateRouterMaster(_router).addLiquidity(1,allUSDC,address(this));
    }
}
