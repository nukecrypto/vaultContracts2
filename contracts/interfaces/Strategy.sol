// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {
    function want() external view returns (address);

    function deposit() external;

    function depositFromVault() external;

    function calcUnderlyingFinalDeposit(uint256)
        external
        view
        returns (uint256);

    // NOTE: must exclude any tokens used in the yield
    // Controller role - withdraw should return to Controller
    function withdraw(address) external;

    // Controller | Vault role - withdraw should always return to Vault
    function withdraw(uint256) external returns (uint256);

    // Controller | Vault role - withdraw should always return to Vault
    function withdrawAll() external returns (uint256);

    function balanceOf() external view returns (uint256);

    function performanceFee() external view returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function PERFORMANCE_MAX() external view returns (uint256);

    function getTotalBalance() external view returns (uint256);

    function getDepositFee() external view returns (uint256);

    function setDepositFee(uint256 _feeRate) external;

    function getWithdrawFee() external view returns (uint256);

    function setWithdrawFee(uint256 _feeRate) external;
}
