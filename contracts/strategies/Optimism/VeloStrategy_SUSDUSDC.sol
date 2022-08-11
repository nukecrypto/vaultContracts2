// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import {BasicStrategy} from "../BasicStrategy.sol";
import "../../interfaces/Velodrome.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Minion} from "../../Minion.sol";
// import "hardhat/console.sol"; // TODO: Remove before deploy

/**
 * @title VeloStrategy_SUSDUSDC
 * @dev Defined strategy(I.e curve 3pool) that inherits structure and functionality from BasicStrategy
 */
contract VeloStrategy_SUSDUSDC is BasicStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address private _veloGaugeDeposit =
        address(0xb03f52D2DB3e758DD49982Defd6AeEFEa9454e80);

    address private _veloLpToken =
        address(0xd16232ad60188B68076a235c65d692090caba155);

    address private _veloRouter =
        address(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9);

    address private _veloToken =
        address(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);

    address private _susdToken =
        address(0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9);

    address private _usdcToken =
        address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    address[] public activeRewardsTokens = [_veloToken];

    int128 private _tokenIndex = 0;
    uint256 private _slippageAllowed = 10000000; // 10000000 = 1%

    constructor(
        address _vault,
        address _wantToken,
        address _poolInvestToken
    ) BasicStrategy(_vault, _wantToken, _poolInvestToken) {}

    /// @return name of the strategy
    function getName() external pure override returns (string memory) {
        return "VeloStrategy_SUSDUSDC";
    }

    /// @dev pre approves max
    function doApprovals() public {
        IERC20(want()).safeApprove(_veloGaugeDeposit, type(uint256).max);
        IERC20(_veloToken).safeApprove(_veloRouter, type(uint256).max);
        IERC20(_susdToken).safeApprove(_veloRouter, type(uint256).max);
        IERC20(_usdcToken).safeApprove(_veloRouter, type(uint256).max);
    }

    /// @notice gives an estimate of tokens invested
    function balanceOfPool() public view override returns (uint256) {
        return ISolidlyGauge(_veloGaugeDeposit).balanceOf(address(this));
    }

    function depositFromVault() public onlyVault {
        _deposit();
    }

    /// @notice invests available funds
    function deposit() public override onlyMinion {
        _deposit();
    }

    /// @notice invests available funds
    function _deposit() internal {

        uint256 availableFundsToDeposit = getAvailableFunds();

        require(availableFundsToDeposit > 0, "No funds available");

        ISolidlyGauge(_veloGaugeDeposit).deposit(availableFundsToDeposit, 0);
    }

    /// @notice withdraws all from pool to strategy where the funds can safetly be withdrawn by it's owners
    /// @dev this is only to be allowed by governance and should only be used in the event of a strategy or pool not functioning correctly/getting discontinued etc
    function withdrawAll() public override onlyGovernance {

        uint256 balanceOfGaugeToken = IERC20(_veloGaugeDeposit).balanceOf(
            address(this)
        ); // get shares

        ISolidlyGauge(_veloGaugeDeposit).withdraw(balanceOfGaugeToken);
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

        ISolidlyGauge(_veloGaugeDeposit).withdraw(_amount);

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

    function _swapSolidlyWithRoute(RouteParams memory routes, uint256 _amount) internal {
        ISolidlyRouter(_veloRouter).swapExactTokensForTokens(_amount, 0, routes, address(this), block.timestamp.add(60));
    }

    function harvest() public onlyMinion {
        ISolidlyGauge(_veloGaugeDeposit).getReward(address(this), activeRewardsTokens);
    }

    /// @notice harvests rewards, sells them for want and reinvests them
    function harvestAndReinvest() public override onlyMinion {
        ISolidlyGauge(_veloGaugeDeposit).getReward(address(this), activeRewardsTokens);

        uint256 rewardAmount = IERC20(_veloToken).balanceOf(
            address(this)
        );

        require(rewardAmount > 0, "No Rewards");


        if (performanceFee > 0) {
            uint256 _fee = calculateFee(rewardAmount, performanceFee);
            IERC20(_veloToken).safeTransfer(feeAddress, _fee);
        }

        rewardAmount = IERC20(_veloToken).balanceOf(
            address(this)
        );

        // Swap Velo to token0/token1
        uint256 _toToken0 = rewardAmount.div(2);
        uint256 _toToken1 = rewardAmount.sub(_toToken0);

        RouteParams[] memory _veloRoute = new RouteParams[](2);
        _veloRoute[0] = RouteParams(_veloToken, _usdcToken, true);
        _veloRoute[1] = RouteParams(_veloToken, _susdToken, true);

//        _swapSolidlyWithRoute(_veloRoute[0], _toToken0);
//        _swapSolidlyWithRoute(_veloRoute[1], _toToken1);

        ISolidlyRouter(_veloRouter).swapExactTokensForTokensSimple(_toToken0, 0, _veloToken, _usdcToken, false,  address(this), block.timestamp.add(60));
        ISolidlyRouter(_veloRouter).swapExactTokensForTokensSimple(_toToken1, 0, _veloToken, _susdToken, false,  address(this), block.timestamp.add(60));

        // Adds in liquidity
        uint256 _token0Amount = IERC20(_usdcToken).balanceOf(address(this));
        uint256 _token1Amount = IERC20(_susdToken).balanceOf(address(this));
        if (_token0Amount > 0 && _token1Amount > 0) {
            ISolidlyRouter(_veloRouter).addLiquidity(
                _usdcToken,
                _susdToken,
                true,
                _token0Amount,
                _token1Amount,
                0,
                0,
                address(this),
                block.timestamp + 60
            );
        }

        _deposit();
    }
}
