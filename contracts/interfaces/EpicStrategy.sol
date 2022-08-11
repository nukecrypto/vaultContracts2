// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface EpicStrategy {
    function want() external view returns (address);

    function deposit() external;

    function calcUnderlyingFinalDeposit(uint256) external view returns (uint256);

    // NOTE: must exclude any tokens used in the yield
    // Controller role - withdraw should return to Controller
    function withdraw(address) external;

    // Controller | Vault role - withdraw should always return to Vault
    function withdraw(uint256) external;

    // Controller | Vault role - withdraw should always return to Vault
    function withdrawAll() external returns (uint256);

    function balanceOf() external view returns (uint256);
}