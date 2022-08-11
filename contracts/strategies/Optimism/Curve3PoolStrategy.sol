// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import {BasicStrategy} from "../BasicStrategy.sol";
import {CurveFactoryDeposit, CurveGauge, SUSDPoolContract, CRVTokenContract} from "../../interfaces/OptimismCurve.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "hardhat/console.sol"; // TODO: Remove before deploy

/**
 * @title Curve3PoolStrategy
 * @dev Defined strategy(I.e curve 3pool) that inherits structure and functionality from BasicStrategy
 */
contract Curve3PoolStrategy is BasicStrategy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address private _curveFactoryDepositAddress =
        address(0x1337BedC9D22ecbe766dF105c9623922A27963EC);
    address private _curvePoolCRVToken =
        address(0x1337BedC9D22ecbe766dF105c9623922A27963EC);
    address private _curveGaugeDeposit =
        address(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    address private _sUSDPoolCRVTokenContractAddress =
        address(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);


    int128 private _tokenIndex = 0;
    uint256 private _slippageAllowed = 10000000; // 10000000 = 1%

    constructor(address _vault, address _wantToken, address _poolInvestToken)
        BasicStrategy(_vault, _wantToken, _poolInvestToken)
    {}

    /// @return name of the strategy
    function getName() external pure override returns (string memory) { // TODO: make setable, immutable?
        return "Curve3PoolStrategy";
    }

    /// @dev pre approves max
    function doApprovals() public {
        IERC20(want()).safeApprove(
            _curveFactoryDepositAddress,
            type(uint256).max
        );
        IERC20(_curvePoolCRVToken).safeApprove(
            _curveGaugeDeposit,
            type(uint256).max
        );
        IERC20(_curvePoolCRVToken).safeApprove(
            _curveFactoryDepositAddress,
            type(uint256).max
        );
    }

    /// @notice gives an estimate of tokens invested
    function balanceOfPool() public view override returns (uint256) {
        uint256 balanceOfGaugeToken = IERC20(_curveGaugeDeposit).balanceOf(
            address(this)
        ); // get shares

        if (balanceOfGaugeToken == 0) {
            return 0;
        }

        uint256 amountInSUSD = CurveFactoryDeposit(_curveFactoryDepositAddress)
            .calc_withdraw_one_coin(
                _curvePoolCRVToken,
                balanceOfGaugeToken,
                _tokenIndex
            );

        return amountInSUSD;
    }

    /// @notice invests available funds
    function deposit() public override onlyGovernance {
        uint256 availableFundsToDeposit = getAvailableFunds();

        require(availableFundsToDeposit > 0, "No funds available");

        uint256[3] memory fundsToDeposit;
        fundsToDeposit = [0, uint256(availableFundsToDeposit), 0];
        uint256 accapetableReturnAmount = calculateAcceptableDifference(
            availableFundsToDeposit,
            100
        ); // 100 = 1%

        CurveFactoryDeposit(_curveFactoryDepositAddress).add_liquidity(
            fundsToDeposit,
            accapetableReturnAmount
        );

        uint256 balanceCurveToken = IERC20(_curvePoolCRVToken).balanceOf(
            address(this)
        );

        require(balanceCurveToken > 0, "!balanceCurveToken");

        CurveGauge(_curveGaugeDeposit).deposit(balanceCurveToken);
    }

    function getCurveFee() public view returns (uint256) {
        uint256 curveFeee = SUSDPoolContract(_curveFactoryDepositAddress).fee();
        return curveFeee;
    }

    function getAdminFee() public view returns (uint256) {
        uint256 adminFee = SUSDPoolContract(_curveFactoryDepositAddress)
            .admin_fee();
        return adminFee;
    }

    /// @notice withdraws all from pool to strategy where the funds can safetly be withdrawn by it's owners
    /// @dev this is only to be allowed by governance and should only be used in the event of a strategy or pool not functioning correctly/getting discontinued etc
    function withdrawAll() public override onlyGovernance {
        uint256 balanceOfGaugeToken = IERC20(_curveGaugeDeposit).balanceOf(
            address(this)
        ); // get shares

        if (balanceOfGaugeToken > 0) {
            // doing this instead of require since there is a risk of funds getting locked in otherwise
            CurveGauge(_curveGaugeDeposit).withdraw(balanceOfGaugeToken);
        }

        uint256 balanceOfCurveToken = IERC20(_curvePoolCRVToken).balanceOf(
            address(this)
        );

        require(balanceOfCurveToken > 0, "Nothing to withdraw");

        uint256 minAccept = balanceOfCurveToken.sub(calculateFee(balanceOfCurveToken, _slippageAllowed));

        CurveFactoryDeposit(_curveFactoryDepositAddress)
            .remove_liquidity_one_coin(
                _curvePoolCRVToken,
                balanceOfCurveToken,
                _tokenIndex,
                minAccept
            );
    }

    /// @notice withdraws a certain amount from the pool
    /// @dev can only be called from inside the contract through the withdraw function which is protected by only vault modifier
    function _withdrawAmount(uint256 _amount)
        internal
        override
        onlyVault
        returns (uint256)
    {
        // TODO: we need to think about what min return we should expect and how to deal with that if it's not enough
        uint256 beforeWithdraw = getAvailableFunds();

        uint256 balanceOfPoolAmount = balanceOfPool();

        if (_amount > balanceOfPoolAmount) {
            _amount = balanceOfPoolAmount;
        }

        uint256[4] memory fundsToWithdraw = [uint256(_amount), 0, 0, 0];

        uint256 neededCRVTokens = CurveFactoryDeposit(
            _curveFactoryDepositAddress
        ).calc_token_amount(_curvePoolCRVToken, fundsToWithdraw, false);

        uint256 balanceOfGaugeToken = IERC20(_curveGaugeDeposit).balanceOf(
            address(this)
        ); // get shares

        require(balanceOfGaugeToken > neededCRVTokens, "not enough funds");

        CurveGauge(_curveGaugeDeposit).withdraw(neededCRVTokens);

        uint256 minAccept = neededCRVTokens.sub(calculateFee(neededCRVTokens, _slippageAllowed));

        CurveFactoryDeposit(_curveFactoryDepositAddress)
            .remove_liquidity_one_coin(
                _curvePoolCRVToken,
                neededCRVTokens,
                _tokenIndex,
                minAccept
            );

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

        uint256 amountThatWasWithdrawn = _withdrawAmount(amountToWithdrawFromCRV);

        availableFunds = getAvailableFunds();

        if(availableFunds < _amount){
            _amount = availableFunds;
        }

        IERC20(wantToken).safeTransfer(__vault, _amount);
        return _amount;
    }

    function harvest() public onlyGovernance {
        CurveGauge(_curveGaugeDeposit).claim_rewards();
    }

    /// @notice harvests rewards, sells them for want and reinvests them
    function harvestAndReinvest() public override onlyGovernance {
        CurveGauge(_curveGaugeDeposit).claim_rewards(); // TODO: is this really needed?
        // CRVTokenContract(_sUSDPoolCRVTokenContractAddress).mint(_curveGaugeDeposit);
        super.harvestAndReinvest();
        deposit();
    }
}
