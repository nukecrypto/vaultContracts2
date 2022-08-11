// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* solhint-disable func-name-mixedcase, var-name-mixedcase */


interface SUSDPoolContract {
  function initialize ( string memory _name, string memory _symbol, address _coin, uint256 _rate_multiplier, uint256 _A, uint256 _fee ) external;
  function decimals (  ) external view returns ( uint256 );
  function transfer ( address _to, uint256 _value ) external returns ( bool );
  function transferFrom ( address _from, address _to, uint256 _value ) external returns ( bool );
  function approve ( address _spender, uint256 _value ) external returns ( bool );
  function permit ( address _owner, address _spender, uint256 _value, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s ) external returns ( bool );
  function admin_fee (  ) external view returns ( uint256 );
  function A (  ) external view returns ( uint256 );
  function A_precise (  ) external view returns ( uint256 );
  function get_virtual_price (  ) external view returns ( uint256 );
  function calc_token_amount ( uint256[2] memory _amounts, bool _is_deposit ) external view returns ( uint256 );
  function add_liquidity ( uint256[2] memory _amounts, uint256 _min_mint_amount ) external returns ( uint256 );
  function add_liquidity ( uint256[2] memory _amounts, uint256 _min_mint_amount, address _receiver ) external returns ( uint256 );
  function get_dy ( int128 i, int128 j, uint256 dx ) external view returns ( uint256 );
  function get_dy_underlying ( int128 i, int128 j, uint256 dx ) external view returns ( uint256 );
  function exchange ( int128 i, int128 j, uint256 _dx, uint256 _min_dy ) external returns ( uint256 );
  function exchange ( int128 i, int128 j, uint256 _dx, uint256 _min_dy, address _receiver ) external returns ( uint256 );
  function exchange_underlying ( int128 i, int128 j, uint256 _dx, uint256 _min_dy ) external returns ( uint256 );
  function exchange_underlying ( int128 i, int128 j, uint256 _dx, uint256 _min_dy, address _receiver ) external returns ( uint256 );
  function remove_liquidity ( uint256 _burn_amount, uint256[2] memory _min_amounts ) external returns ( uint256[2] memory );
  function remove_liquidity ( uint256 _burn_amount, uint256[2] memory _min_amounts, address _receiver ) external returns ( uint256[2] memory );
  function remove_liquidity_imbalance ( uint256[2] memory _amounts, uint256 _max_burn_amount ) external returns ( uint256 );
  function remove_liquidity_imbalance ( uint256[2] memory _amounts, uint256 _max_burn_amount, address _receiver ) external returns ( uint256 );
  function calc_withdraw_one_coin ( uint256 _burn_amount, int128 i ) external view returns ( uint256 );
  function remove_liquidity_one_coin ( uint256 _burn_amount, int128 i, uint256 _min_received ) external returns ( uint256 );
  function remove_liquidity_one_coin ( uint256 _burn_amount, int128 i, uint256 _min_received, address _receiver ) external returns ( uint256 );
  function ramp_A ( uint256 _future_A, uint256 _future_time ) external;
  function stop_ramp_A (  ) external;
  function admin_balances ( uint256 i ) external view returns ( uint256 );
  function withdraw_admin_fees (  ) external;
  function version (  ) external view returns ( string memory);
  function coins ( uint256 arg0 ) external view returns ( address );
  function balances ( uint256 arg0 ) external view returns ( uint256 );
  function fee (  ) external view returns ( uint256 );
  function initial_A (  ) external view returns ( uint256 );
  function future_A (  ) external view returns ( uint256 );
  function initial_A_time (  ) external view returns ( uint256 );
  function future_A_time (  ) external view returns ( uint256 );
  function name (  ) external view returns ( string memory );
  function symbol (  ) external view returns ( string memory);
  function balanceOf ( address arg0 ) external view returns ( uint256 );
  function allowance ( address arg0, address arg1 ) external view returns ( uint256 );
  function totalSupply (  ) external view returns ( uint256 );
  function DOMAIN_SEPARATOR (  ) external view returns ( bytes32 );
  function nonces ( address arg0 ) external view returns ( uint256 );
}


interface CurveFactoryDeposit {
    function add_liquidity(
        address _pool,
        uint256[4] memory _deposit_amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);

    function add_liquidity(
        address _pool,
        uint256[4] memory _deposit_amounts,
        uint256 _min_mint_amount,
        address _receiver
    ) external returns (uint256);

    function add_liquidity(
        uint256[3] memory _amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);

    function remove_liquidity(
        address _pool,
        uint256 _burn_amount,
        uint256[4] memory _min_amounts
    ) external returns (uint256[4] memory);

    function remove_liquidity(
        address _pool,
        uint256 _burn_amount,
        uint256[4] memory _min_amounts,
        address _receiver
    ) external returns (uint256[4] memory);

    function remove_liquidity_one_coin(
        address _pool,
        uint256 _burn_amount,
        int128 i,
        uint256 _min_amount
    ) external returns (uint256);

    function remove_liquidity_one_coin(
        address _pool,
        uint256 _burn_amount,
        int128 i,
        uint256 _min_amount,
        address _receiver
    ) external returns (uint256);

    function remove_liquidity_imbalance(
        address _pool,
        uint256[4] memory _amounts,
        uint256 _max_burn_amount
    ) external returns (uint256);

    function remove_liquidity_imbalance(
        address _pool,
        uint256[4] memory _amounts,
        uint256 _max_burn_amount,
        address _receiver
    ) external returns (uint256);

    function calc_withdraw_one_coin(
        address _pool,
        uint256 _token_amount,
        int128 i
    ) external view returns (uint256);

    function calc_token_amount(
        address _pool,
        uint256[4] memory _amounts,
        bool _is_deposit
    ) external view returns (uint256);

    function fee() external view returns(uint256);
}

interface CurveGauge {
    function deposit(uint256 _value) external;

    function deposit(uint256 _value, address _user) external;

    function deposit(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external;

    function withdraw(uint256 _value) external;

    function withdraw(uint256 _value, address _user) external;

    function withdraw(
        uint256 _value,
        address _user,
        bool _claim_rewards
    ) external;

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool);

    function approve(address _spender, uint256 _value) external returns (bool);

    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool);

    function transfer(address _to, uint256 _value) external returns (bool);

    function increaseAllowance(address _spender, uint256 _added_value)
        external
        returns (bool);

    function decreaseAllowance(address _spender, uint256 _subtracted_value)
        external
        returns (bool);

    function user_checkpoint(address addr) external returns (bool);

    function claimable_tokens(address addr) external returns (uint256);

    function claimed_reward(address _addr, address _token)
        external
        view
        returns (uint256);

    function claimable_reward(address _user, address _reward_token)
        external
        view
        returns (uint256);

    function set_rewards_receiver(address _receiver) external;

    function claim_rewards() external;

    function claim_rewards(address _addr) external;

    function claim_rewards(address _addr, address _receiver) external;

    function add_reward(address _reward_token, address _distributor) external;

    function set_reward_distributor(address _reward_token, address _distributor)
        external;

    function deposit_reward_token(address _reward_token, uint256 _amount)
        external;

    function set_manager(address _manager) external;

    function update_voting_escrow() external;

    function set_killed(bool _is_killed) external;

    function decimals() external view returns (uint256);

    function integrate_checkpoint() external view returns (uint256);

    function version() external view returns (string memory);

    function factory() external view returns (address);

    function initialize(address _lp_token, address _manager) external;

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function nonces(address arg0) external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function allowance(address arg0, address arg1)
        external
        view
        returns (uint256);

    function balanceOf(address arg0) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function lp_token() external view returns (address);

    function manager() external view returns (address);

    function voting_escrow() external view returns (address);

    function working_balances(address arg0) external view returns (uint256);

    function working_supply() external view returns (uint256);

    function period() external view returns (uint256);

    function period_timestamp(uint256 arg0) external view returns (uint256);

    function integrate_checkpoint_of(address arg0)
        external
        view
        returns (uint256);

    function integrate_fraction(address arg0) external view returns (uint256);

    function integrate_inv_supply(uint256 arg0) external view returns (uint256);

    function integrate_inv_supply_of(address arg0)
        external
        view
        returns (uint256);

    function reward_count() external view returns (uint256);

    function reward_tokens(uint256 arg0) external view returns (address);

    //   function reward_data ( address arg0 ) external view returns ( tuple );
    function rewards_receiver(address arg0) external view returns (address);

    function reward_integral_for(address arg0, address arg1)
        external
        view
        returns (uint256);

    function is_killed() external view returns (bool);

    function inflation_rate(uint256 arg0) external view returns (uint256);
}

interface CRVTokenContract {
  function mint ( address _gauge ) external;
  function mint_many (address[32] memory _gauges ) external;
  function deploy_gauge ( address _lp_token, bytes32 _salt ) external returns ( address );
  function deploy_gauge ( address _lp_token, bytes32 _salt, address _manager ) external returns ( address );
  function set_voting_escrow ( address _voting_escrow ) external;
  function set_implementation ( address _implementation ) external;
  function set_mirrored ( address _gauge, bool _mirrored ) external;
  function set_call_proxy ( address _new_call_proxy ) external;
  function commit_transfer_ownership ( address _future_owner ) external;
  function accept_transfer_ownership (  ) external;
  function is_valid_gauge ( address _gauge ) external view returns ( bool );
  function is_mirrored ( address _gauge ) external view returns ( bool );
  function last_request ( address _gauge ) external view returns ( uint256 );
  function get_implementation (  ) external view returns ( address );
  function voting_escrow (  ) external view returns ( address );
  function owner (  ) external view returns ( address );
  function future_owner (  ) external view returns ( address );
  function call_proxy (  ) external view returns ( address );
  function gauge_data ( address arg0 ) external view returns ( uint256 );
  function minted ( address arg0, address arg1 ) external view returns ( uint256 );
  function get_gauge_from_lp_token ( address arg0 ) external view returns ( address );
  function get_gauge_count (  ) external view returns ( uint256 );
  function get_gauge ( uint256 arg0 ) external view returns ( address );
}

/* solhint-enable func-name-mixedcase, var-name-mixedcase */