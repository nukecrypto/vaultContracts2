// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import {Governable} from "./Governable.sol";

/**
* @title Minion
* @dev The Minion contract has an minion address, and provides basic authorization control
* functions, this simplifies the implementation of "user permissions".
*/
abstract contract Minion is Governable {
  address private _minion;
  address private _proposedMinion;

  event MinionTransferred(
    address indexed previousMinion,
    address indexed newMinion
  );

  event NewMinionProposed(
    address indexed previousMinion,
    address indexed newMinion
  );

  /**
  * @dev The Governed constructor sets the original `owner` of the contract to the sender
  * account.
  */
  constructor() {
    _minion = msg.sender;
    _proposedMinion = msg.sender;
    emit MinionTransferred(address(0), _minion);
  }

  /**
  * @return the address of the minion.
  */
  function minion() public view returns(address) {
    return _minion;
  }

  /**
  * @dev Throws if called by any account other than the minion.
  */
  modifier onlyMinion() {
    require(isMinion(), "!Minion");
    _;
  }

  /**
  * @return true if `msg.sender` is the minion of the contract.
  */
  function isMinion() public view returns(bool) {
    return msg.sender == _minion;
  }

  /**
  * @dev Allows the current minion to propose transfer of control of the contract to a new minion.
  * @param newMinion The address to transfer minion to.
  */
  function proposeMinion(address newMinion) public onlyGovernance {
    _proposeMinion(newMinion);
  }

  /**
  * @dev Proposes a new minion.
  * @param newMinion The address to propose minion to.
  */
  function _proposeMinion(address newMinion) internal {
    require(newMinion != address(0), "!address(0)");
    emit NewMinionProposed(_minion, newMinion);
    _proposedMinion = newMinion;
  }

  /**
  * @dev Transfers control of the contract to a new minion if the calling address is the same as the proposed one.
   */
  function acceptMinion() public {
    _acceptMinion();
  }

  /**
  * @dev Transfers control of the contract to a new Minion.
  */
  function _acceptMinion() internal {
    require(msg.sender == _proposedMinion, "!ProposedMinion");
    emit MinionTransferred(_minion, msg.sender);
    _minion = msg.sender;
  }
}
