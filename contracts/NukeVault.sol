// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "./interfaces/EIP4626.sol";
import {FixedPointMathLib} from "./temporaryContracts/utils/FixedPointMathLib.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IStrategy} from "./interfaces/Strategy.sol";
import {Minion} from "./Minion.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

contract NukeVault is ERC20, IERC4626, Minion, Pausable {
    uint256 public totalFloat;
    using SafeERC20 for ERC20;
    address public controller;
    ERC20 private immutable _asset;
    using FixedPointMathLib for uint256;
    using SafeMath for uint256;

    address public strategy;
    address public _feeAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public _depositFee = 0; // 10000000 = 1% 
    uint256 public _withdrawFee = 0; // 5000000 = 0.5%

    uint256 public constant MAX_FLOAT_FEE = 10000000000; // 100%, 1e10 precision.

    constructor(
        address __asset,
        string memory _name,
        string memory _symbol
    )
        ERC20(
            string(abi.encodePacked("Nuke Vault ", _name)),
            string(abi.encodePacked("nuke", _symbol))
        )
    {
        _asset = ERC20(__asset);
    }

    /**
     * @dev The address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault. TALK!
     * - MUST NOT revert.
     */
    /// @notice Sum of idle funds and funds deployed to Strategy.
    function totalAssets() public view override returns (uint256) {
        // should return assets in vault + assets in strategies if strategy is connected
        if (strategy == address(0)) {
            return idleFloat();
        }

        return idleFloat() + IStrategy(strategy).getTotalBalance(); // _asset.balanceOf(address(strategy));
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    /**
     * @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
     * through a deposit call.
     *
     * - MUST return a limited value if receiver is subject to some deposit limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
     * - MUST NOT revert.
     */
    /// @notice Optional. Left empty here. (No limit)
    function maxDeposit(address)
        public
        pure
        override
        returns (uint256 maxAssets)
    {
        return type(uint256).max;
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
     *   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
     *   in the same transaction.
     * - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
     *   deposit would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause deposit to revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        uint256 depositFee = _calculateFee(assets, _depositFee);

        return convertToShares(assets.sub(depositFee));
    }

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   deposit execution, and are accounted for during deposit.
     * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        returns (uint256 shares)
    {
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more then max"
        );
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // assets = assets.sub(depositFee);

        // if _asset is ERC777, transferFrom can call reenter BEFORE the transfer happens through
        // the tokensToSend hook, so we need to transfer before we mint to keep the invariants.
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        if (_depositFee > 0) {
            uint256 depositFee = _calculateFee(assets, _depositFee);
            _asset.approve(address(this), depositFee);
            _asset.safeTransferFrom(address(this), _feeAddress, depositFee);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /**
     * @dev Returns the maximum amount of the Vault shares that can be minted for the receiver, through a mint call.
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of shares that may be minted.
     * - MUST NOT revert.
     */
    /// @notice Optional. Left empty here. (No limit)
    function maxMint(address) public pure override returns (uint256 maxShares) {
        return type(uint256).max;
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of assets that would be deposited in a mint call
     *   in the same transaction. I.e. mint should return the same or fewer assets as previewMint if called in the
     *   same transaction.
     * - MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint
     *   would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause mint to revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewMint SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by minting.
     */
    function previewMint(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        uint256 assetsCost = convertToAssets(shares);
        uint256 depositFee = _calculateFee(assetsCost, _depositFee);

        return
            assetsCost == 0
                ? 1
                : assetsCost.add(depositFee);
    }

    /**
     * @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the mint
     *   execution, and are accounted for during mint.
     * - MUST revert if all of shares cannot be minted (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        returns (uint256 assets)
    {
        require(shares <= maxMint(receiver), "ERC4626: mint more then max");

        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        _asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        if (_depositFee > 0) {
            uint256 assetsToCalculateFee = convertToAssets(shares);
            uint256 depositFee = _calculateFee(
                assetsToCalculateFee,
                _depositFee
            );
            _asset.approve(address(this), depositFee);
            _asset.safeTransferFrom(address(this), _feeAddress, depositFee);
        }

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /**
     * @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     *
     *
     * - MUST return the maximum amount of assets that could be transferred from owner through withdraw and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * - MUST factor in both global and user-specific limits, like if withdrawals are entirely disabled (even temporarily) it MUST return 0.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner)
        public
        view
        override
        returns (uint256 maxAssets)
    {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
     *   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
     *   called
     *   in the same transaction.
     * - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
     *   the withdrawal would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause withdraw to revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewWithdraw SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        uint256 withdrawFee = _calculateFee(assets, _withdrawFee);

        uint256 assetsWithFee = assets.add(withdrawFee);
        shares = convertToShares(assetsWithFee);

        return shares.add((convertToAssets(shares) < assetsWithFee ? 1 : 0));
    }

    /**
     * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MUST support a withdraw flow where the shares are burned from owner directly where owner is msg.sender or msg.sender has ERC-20 approval over
     * the shares of owner. MAY support an additional flow in which the shares are transferred to the Vault contract before the withdraw execution, and are accounted for during withdraw.
     * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more then max"
        );

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            
            //     uint256 allowed = allowance(owner, msg.sender); // Saves gas for limited approvals.

            // if (allowed != type(uint256).max) {
            _spendAllowance(owner, msg.sender, shares);
            // }
        }

        _burn(owner, shares);

        uint256 withdrawFee = _calculateFee(assets, _withdrawFee);

        uint256 actualAssetsWithdrawn = beforeWithdraw(assets.add(withdrawFee));

        if (_withdrawFee > 0) {
            // pay the fees
            uint256 nukeVaultFee = _calculateFee(actualAssetsWithdrawn, _withdrawFee);
            _asset.approve(address(this), nukeVaultFee);
            _asset.safeTransferFrom(address(this), _feeAddress, nukeVaultFee);
            actualAssetsWithdrawn = actualAssetsWithdrawn.sub(nukeVaultFee);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        _asset.safeTransfer(receiver, actualAssetsWithdrawn);
        return shares;
    }

    /**
     * @dev Maximum amount of Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
     *
     * - MUST return the maximum amount of shares that could be transferred from owner through redeem and not cause a revert, which MUST NOT be higher than the actual maximum that would be accepted (it should underestimate if necessary).
     * - MUST factor in both global and user-specific limits, like if redemption is entirely disabled (even temporarily) it MUST return 0.
     * - MUST NOT revert.
     */
    function maxRedeem(address owner)
        public
        view
        override
        returns (uint256 maxShares)
    {
        return balanceOf(owner);
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
     *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
     *   same transaction.
     * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
     *   redemption would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert due to vault specific user/global limits. MAY revert due to other conditions that would also cause redeem to revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
     */
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        assets = convertToAssets(shares);
        uint256 withdrawCost = _calculateFee(assets, _withdrawFee);
        return assets.sub(withdrawCost);
    }

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MUST support a redeem flow where the shares are burned from owner directly where owner is msg.sender or msg.sender has ERC-20 approval over
     * the shares of owner.
     * - MAY support an additional flow in which the shares are transferred to the Vault contract before the redeem execution, and are accounted for during redeem.
     * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more then max");

        assets = previewRedeem(shares);
        // Check for rounding error since we round down in previewRedeem.
        require(assets != 0, "ZERO_ASSETS");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 amountIncFees = convertToAssets(shares);

        _burn(owner, shares);

        uint256 actualAmountWithdrawn = beforeWithdraw(amountIncFees);
        
        if (_withdrawFee > 0) {
            
            uint256 withdrawFee = _calculateFee(
                actualAmountWithdrawn,
                _withdrawFee
            );
            _asset.approve(address(this), withdrawFee);
            _asset.safeTransferFrom(address(this), _feeAddress, withdrawFee);
            actualAmountWithdrawn = actualAmountWithdrawn.sub(withdrawFee);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        _asset.safeTransfer(receiver, actualAmountWithdrawn);

        return assets;
    }

    /*///////////////////////////////////////////////////////////////
                         INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Pull funds from strategy to Vault if needed.
    /// Withdraw at least requested amount to the Vault. Covers withdraw/performance fees of strat. Leaves dust tokens.
    function beforeWithdraw(uint256 amount)
        internal
        returns (uint256 actualAmount)
    {
        uint256 idleAmountsVault = idleFloat();

        if (idleAmountsVault < amount) {
            uint256 differenceToWithdrawFromStrategy = amount.sub(idleAmountsVault);

            actualAmount = IStrategy(strategy).withdraw(
                differenceToWithdrawFromStrategy
            );
            return idleAmountsVault.add(actualAmount);
        }

        return amount;
    }

    function afterDeposit(uint256 assets, uint256 shares) internal {}

    /*///////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Idle funds in Vault, i.e deposits before invest()
    function idleFloat() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                            Nuke Vaults FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice moves funds from vault to strategy
    function invest() public onlyMinion {
        uint256 _bal = idleFloat();
        require(_bal > 0, "No funds to invest");
        _asset.safeTransfer(strategy, _bal);
        IStrategy(strategy).depositFromVault();
    }

    /// @notice this is used to transfer tokens other than want that got stuck or accidently transfered to this contract
    function inCaseTokensGetStuck(address _token, uint256 _amount)
        public
        onlyGovernance
    {
        require(_token != address(_asset), "token");
        ERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice used to set the strategy that the vault uses
    function setStrategy(address _strategy) public onlyGovernance {
        require(IStrategy(_strategy).want() == address(_asset), "!token");

        require(strategy == address(0), "Strategy already set"); // only allowed once in order to protect against rug pull

        strategy = _strategy;
    }

    /// @notice sets address that fees are paid to
    function setFeeAddress(address __feeAddress) public onlyGovernance {
        _feeAddress = __feeAddress;
    }

    /// @notice sets deposit fee rate
    function setDepositFee(uint256 __depositFee) public onlyGovernance {
        require(_depositFee < 200000000, "Max fee reached");
        _depositFee = __depositFee;
    }

    /// @notice sets withdraw fee rate
    function setWithdrawFee(uint256 __withdrawFee) public onlyGovernance {
        require(__withdrawFee < 200000000, "Max fee reached");
        _withdrawFee = __withdrawFee;
    }

    /// @notice deposits all of senders tokens into the contract
    function depositAll() public whenNotPaused {
        deposit(_asset.balanceOf(msg.sender), msg.sender);
    }

    /// @notice withdraws all of senders funds to sender
    function withdrawAll() external {
        redeem(balanceOf(msg.sender), msg.sender, msg.sender);
    }

    /// @dev calulcates fee given an amount and a fee rate
    function _calculateFee(uint256 _amount, uint256 _feeRate)
        internal
        pure
        returns (uint256 _fee)
    {
        return (_amount * _feeRate) / MAX_FLOAT_FEE;
    }

    /// @dev Pause the contract
    function pause() external onlyGovernance {
        _pause();
    }

    /// @dev Unpause the contract
    function unpause() external onlyGovernance {
        _unpause();
    }

    function getPricePerFullShare() public view returns (uint256) {
        return convertToAssets(1e18);
    }

    function balance() public view returns (uint256) {
        return totalAssets();
    }
}
