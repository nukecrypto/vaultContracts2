// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Minion} from "../Minion.sol";
import {VaultConnected} from "../VaultConnected.sol";
import {ISwapRouter03, IV3SwapRouter} from "../interfaces/Uniswap.sol";

/**
 * @title BasicStrategy
 * @dev Defines structure and basic functionality of strategies
 */
contract BasicStrategy is VaultConnected, Minion {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable wantToken;
    address public immutable poolInvestToken;

    address[] public rewards;

    uint24 internal _poolFee = 3000;
    uint256 public performanceFee = 0;
    address public feeAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant MAX_FLOAT_FEE = 10000000000; // 100%, 1e10 precision.
    uint256 public lifetimeEarned = 0;

    address payable public univ3Router2 =
        payable(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    mapping(address => bool) private approvedTokens;

    // not sure we need indexed
    event HarvestAndReinvest(
        uint256 indexed amountTraded,
        uint256 indexed amountReceived
    );

    event Harvest(uint256 wantEarned, uint256 lifetimeEarned);

    constructor(address _vault, address _wantToken, address _poolInvestToken) VaultConnected(_vault) {
        wantToken = _wantToken;
        poolInvestToken = _poolInvestToken;
    }

    /// @return name of the strategy
    function getName() external pure virtual returns (string memory) {
        return "BasicStrategy";
    }

    /// @notice invests available funds
    function deposit() public virtual onlyMinion {
    }

    /// @notice withdraws all from pool to strategy where the funds can safetly be withdrawn by it's owners
    /// @dev this is only to be allowed by governance and should only be used in the event of a strategy or pool not functioning correctly/getting discontinued etc
    function withdrawAll() public virtual onlyGovernance {
    }

    /// @notice withdraws a certain amount from the pool
    /// @dev can only be called from inside the contract through the withdraw function which is protected by only vault modifier
    function _withdrawAmount(uint256 _amount)
        internal
        virtual
        onlyVault
        returns (uint256)
    {
    }

    /// @dev returns nr of curve tokens that are not yet gauged
    function getAvailableFunds() public view returns (uint256) {
        return IERC20(wantToken).balanceOf(address(this));
    }

    /// @dev returns nr of funds that are not yet invested
    function getAvailablePoolInvestTokens() public view returns (uint256) {
        return IERC20(poolInvestToken).balanceOf(address(this));
    }

    /// @notice gives an estimate of tokens invested
    /// @dev returns an estimate of tokens invested
    function balanceOfPool() public view virtual returns (uint256) {
        return 0;
    }

    /// @notice gets the total amount of funds held by this strategy
    /// @dev returns total amount of available and invested funds
    function getTotalBalance() public view returns (uint256) { // TODO: Maybe add the susd/poolInvestToken somehow as well...not sure
        uint256 investedFunds = balanceOfPool();
        uint256 availableFunds = getAvailableFunds();

        return investedFunds.add(availableFunds);
    }

    /// @notice sells rewards for want and reinvests them
    function harvestAndReinvest() public virtual onlyMinion {
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] == address(0)) {
                continue;
            }

            uint256 balanceOfCurrentReward = IERC20(rewards[i]).balanceOf(
                address(this)
            );

            if (balanceOfCurrentReward < 1) {
                continue;
            }

            if (approvedTokens[rewards[i]] == false) {
                IERC20(rewards[i]).safeApprove(univ3Router2, type(uint256).max);
                approvedTokens[rewards[i]] = true;
            }

            uint256 amountOut = ISwapRouter03(univ3Router2).exactInput(
                IV3SwapRouter.ExactInputParams({
                    path: abi.encodePacked(
                        rewards[i],
                        _poolFee,
                        ISwapRouter03(univ3Router2).WETH9(),
                        _poolFee,
                        poolInvestToken
                    ),
                    recipient: address(this),
                    amountIn: balanceOfCurrentReward,
                    amountOutMinimum: 0
                })
            );

            /// @notice Keep this in so you get paid!
            if (performanceFee > 0 && amountOut > 0) {
                uint256 _fee = calculateFee(amountOut, performanceFee);
                IERC20(poolInvestToken).safeTransfer(feeAddress, _fee);
            }

            lifetimeEarned = lifetimeEarned.add(amountOut);
            emit Harvest(amountOut, lifetimeEarned);
            emit HarvestAndReinvest(balanceOfCurrentReward, amountOut);
        }
    }

    /// @notice call to withdraw funds to vault
    function withdraw(uint256 _amount)
        external
        virtual
        onlyVault
        returns (uint256)
    {
        uint256 availableFunds = getAvailableFunds();

        if (availableFunds >= _amount) {
            IERC20(wantToken).safeTransfer(__vault, _amount);
            return _amount;
        }

        uint256 amountThatWasWithdrawn = _withdrawAmount(_amount);

        IERC20(wantToken).safeTransfer(__vault, amountThatWasWithdrawn);
        return amountThatWasWithdrawn;
    }

    /// @notice returns address of want token(I.e token that this strategy aims to accumulate)
    function want() public view returns (address) {
        return wantToken;
    }

    /// @dev calculates acceptable difference, used when setting an acceptable min of return
    /// @param _amount amount to calculate percentage of
    /// @param _differenceRate percentage rate to use
    function calculateAcceptableDifference(
        uint256 _amount,
        uint256 _differenceRate
    ) internal pure returns (uint256 _fee) {
        return _amount.sub((_amount * _differenceRate) / 10000); // 100%
    }

    /// @dev adds address of an expected reward to be yielded from the strategy, looks for a empty slot in the array before creating extra space in array in order to save gas
    /// @param _reward address of reward token
    function addReward(address _reward) public onlyGovernance {

        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] == _reward) {
                // address already exists, return
                return;
            }
        }

        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] == address(0)) {
                rewards[i] = _reward;
                return;
            }
        }
        rewards.push(_reward);
    }

    /// @dev looks for an address of a token in the rewards array and resets it to zero instead of popping it, this in order to save gas
    function removeReward(address _reward) public onlyGovernance {
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i] == _reward) {
                rewards[i] = address(0);
                return;
            }
        }
    }

    /// @dev resets all addresses of rewards to zero
    function clearRewards() public onlyGovernance {
        for (uint256 i = 0; i < rewards.length; i++) {
            rewards[i] = address(0);
        }
    }

    /// @dev returns rewards that this strategy yields and later converts to want
    function getRewards() public view returns (address[] memory) {
        return rewards;
    }

    /// @dev gets pool fee rate
    function getPoolFee() public view returns (uint24) {
        return _poolFee;
    }

    /// @dev sets pool fee rate
    function setPoolFee(uint24 _feeRate) public onlyGovernance {
        _poolFee = _feeRate;
    }

    /// @notice sets address that fees are paid to
    function setPerformanceFeeAddress(address _feeAddress) public onlyGovernance {
        feeAddress = _feeAddress;
    }

    /// @notice sets performance fee rate
    function setPerformanceFee(uint256 _performanceFee) public onlyGovernance {
        require(_performanceFee < 2000000000, "Max fee reached");
        performanceFee = _performanceFee;
    }

    /// @dev calulcates fee given an amount and a fee rate
    function calculateFee(uint256 _amount, uint256 _feeRate)
        public
        pure
        returns (uint256 _fee)
    {
        return (_amount * _feeRate) / MAX_FLOAT_FEE;
    }
}
