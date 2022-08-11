// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/**
* @title Governable
* @dev The Governable contract has an governance address, and provides basic authorization control
* functions, this simplifies the implementation of "user permissions".
*/
abstract contract Governable {
  address private _governance;
  address private _proposedGovernance;

  event GovernanceTransferred(
    address indexed previousGovernance,
    address indexed newGovernance
  );

  event NewGovernanceProposed(
    address indexed previousGovernance,
    address indexed newGovernance
  );

  /**
  * @dev The Governed constructor sets the original `owner` of the contract to the sender
  * account.
  */
  constructor() {
    _governance = msg.sender;
    _proposedGovernance = msg.sender;
    emit GovernanceTransferred(address(0), _governance);
  }

  /**
  * @return the address of the governance.
  */
  function governance() public view returns(address) {
    return _governance;
  }

  /**
  * @dev Throws if called by any account other than the governance.
  */
  modifier onlyGovernance() {
    require(isGovernance(), "!Governance");
    _;
  }

  /**
  * @return true if `msg.sender` is the governance of the contract.
  */
  function isGovernance() public view returns(bool) {
    return msg.sender == _governance;
  }

  /**
  * @dev Allows the current governance to propose transfer of control of the contract to a new governance.
  * @param newGovernance The address to transfer governance to.
  */
  function proposeGovernance(address newGovernance) public onlyGovernance {
    _proposeGovernance(newGovernance);
  }

  /**
  * @dev Proposes a new governance.
  * @param newGovernance The address to propose governance to.
  */
  function _proposeGovernance(address newGovernance) internal {
    require(newGovernance != address(0), "!address(0)");
    emit NewGovernanceProposed(_governance, newGovernance);
    _proposedGovernance = newGovernance;
  }

  /**
  * @dev Transfers control of the contract to a new governance if the calling address is the same as the proposed one.
   */
  function acceptGovernance() public {
    _acceptGovernance();
  }

  /**
  * @dev Transfers control of the contract to a new governance.
  */
  function _acceptGovernance() internal {
    require(msg.sender == _proposedGovernance, "!ProposedGovernance");
    emit GovernanceTransferred(_governance, msg.sender);
    _governance = msg.sender;
  }
}
