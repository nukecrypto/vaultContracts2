// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import {BasicStrategy} from "../BasicStrategy.sol";
import {CurveFactoryDeposit, CurveGauge, SUSDPoolContract, CRVTokenContract} from "../../interfaces/OptimismCurve.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
/**
 * @title CurveSusdStrategy
 * @dev Defined strategy(I.e susd curve pool) that inherits structure and functionality from BasicStrategy
 */
contract CurveSusdStrategy is BasicStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address private _curveFactoryDepositAddress =
        address(0x167e42a1C7ab4Be03764A2222aAC57F5f6754411);
    address private _sUSDCurve3PoolToken =
        address(0x061b87122Ed14b9526A813209C8a59a633257bAb);
    address private _sUSDCurve3GaugeDeposit =
        address(0xc5aE4B5F86332e70f3205a8151Ee9eD9F71e0797);
    address private _sUSDPoolCRVTokenContractAddress =
        address(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);
    int128 private _tokenIndex = 0;
    uint256 private _slippageAllowed = 10000000; // 10000000 = 1%

    constructor(
        address _vault,
        address _wantToken,
        address _poolInvestToken
    ) BasicStrategy(_vault, _wantToken, _poolInvestToken) {}

    /// @return name of the strategy
    function getName() external pure override returns (string memory) {
        return "CurveSUSDStrategy";
    }

    /// @dev pre approves max
    function doApprovals() public onlyGovernance {
        IERC20(poolInvestToken).safeApprove(
            _curveFactoryDepositAddress,
            type(uint256).max
        );
        IERC20(_sUSDCurve3PoolToken).safeApprove(
            _sUSDCurve3GaugeDeposit,
            type(uint256).max
        );
        IERC20(_sUSDCurve3PoolToken).safeApprove(
            _curveFactoryDepositAddress,
            type(uint256).max
        );
    }

    /// @notice gives an estimate of tokens invested
    function balanceOfPool() public view override returns (uint256) {
        uint256 balanceOfGaugeToken = CurveGauge(_sUSDCurve3GaugeDeposit)
            .balanceOf(address(this)); // get shares

        return balanceOfGaugeToken;
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
        uint256 availableTokensToDeposit = getAvailablePoolInvestTokens();

        if (availableTokensToDeposit > 0) {
            // require(availableTokensToDeposit > 0, "No funds available");

            uint256[4] memory fundsToDeposit;
            fundsToDeposit = [uint256(availableTokensToDeposit), 0, 0, 0];
            uint256 accapetableReturnAmount = calculateAcceptableDifference(
                availableTokensToDeposit,
                100
            ); // 100 = 1%

            CurveFactoryDeposit(_curveFactoryDepositAddress).add_liquidity(
                _sUSDCurve3PoolToken,
                fundsToDeposit,
                accapetableReturnAmount
            );
        }

        uint256 balanceCurveToken = IERC20(_sUSDCurve3PoolToken).balanceOf(
            address(this)
        );

        require(balanceCurveToken > 0, "!balanceCurveToken");

        CurveGauge(_sUSDCurve3GaugeDeposit).deposit(balanceCurveToken);
    }

    function getCurveFee() public view returns (uint256) {
        uint256 curveFeee = SUSDPoolContract(_sUSDCurve3PoolToken).fee();
        return curveFeee;
    }

    function getAdminFee() public view returns (uint256) {
        uint256 adminFee = SUSDPoolContract(_sUSDCurve3PoolToken).admin_fee();
        return adminFee;
    }

    /// @notice withdraws all from pool to strategy where the funds can safetly be withdrawn by it's owners
    /// @dev this is only to be allowed by governance and should only be used in the event of a strategy or pool not functioning correctly/getting discontinued etc
    function withdrawAll() public override onlyGovernance {
        uint256 balanceOfGaugeToken = CurveGauge(_sUSDCurve3GaugeDeposit)
            .balanceOf(address(this)); // get shares

        if (balanceOfGaugeToken > 0) {
            // doing this instead of require since there is a risk of funds getting locked in otherwise
            CurveGauge(_sUSDCurve3GaugeDeposit).withdraw(balanceOfGaugeToken);
        }

        uint256 balanceOfCurveToken = IERC20(_sUSDCurve3PoolToken).balanceOf(
            address(this)
        );

        require(balanceOfCurveToken > 0, "Nothing to withdraw");

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

        CurveGauge(_sUSDCurve3GaugeDeposit).withdraw(_amount);

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

        uint256 amountToWithdrawFromCRV = _amount.sub(availableFunds);

        _withdrawAmount(amountToWithdrawFromCRV);

        availableFunds = getAvailableFunds();

        if (availableFunds < _amount) {
            _amount = availableFunds;
        }

        IERC20(wantToken).safeTransfer(__vault, _amount);
        return _amount;
    }

    function harvest() public onlyMinion {
        CRVTokenContract(_sUSDPoolCRVTokenContractAddress).mint(
            _sUSDCurve3GaugeDeposit
        );
    }

    /// @notice harvests rewards, sells them for want and reinvests them
    function harvestAndReinvest() public override onlyMinion {
        CRVTokenContract(_sUSDPoolCRVTokenContractAddress).mint(
            _sUSDCurve3GaugeDeposit
        );
        super.harvestAndReinvest();
        deposit();
    }
}
