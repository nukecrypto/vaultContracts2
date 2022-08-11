// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/**
* @title VaultConnected
* @dev The VaultConnected contract has a vault address, and provides basic authorization control
* functions, this simplifies the implementation of "user permissions".
*/
abstract contract VaultConnected {
  address immutable internal __vault;

  /**
  * @dev called with address to vault to connect to
  */
  constructor(address _vault) {
    __vault = _vault;
  }

  /**
  * @return the address of the vault.
  */
  function connectedVault() public view returns(address) {
    return __vault;
  }

  /**
  * @dev Throws if called by any address other than the vault.
  */
  modifier onlyVault() {
    require(isConnected(), "!isConnected");
    _;
  }

  /**
  * @return true if `msg.sender` is the connected vault.
  */
  function isConnected() public view returns(bool) {
    return msg.sender == __vault;
  }
}
