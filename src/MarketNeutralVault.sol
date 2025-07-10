// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {ReentrancyGuard} from "lib/solmate/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

import {IMarketNeutralVault} from "./interfaces/IMarketNeutralVault.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

/**
 * @title market neutral vault
 * @author defi strategies team
 * @notice vault that maintains market neutral exposure through spot and perpetual positions
 * @dev accepts USDC deposits and manages portfolio across multiple strategies to maintain market neutrality
 */
contract MarketNeutralVault is IMarketNeutralVault, ERC20, Owned, ReentrancyGuard {
    using SafeTransferLib for IERC20;
    using FixedPointMathLib for uint256;

    error ZeroAddress();
    error ZeroAmount();
    error StrategyNotSet();
    error InsufficientBalance();
    error VaultPaused();
    error NotPositionManager();
    error RebalanceNotNeeded();
    error PositionManagerNotSet();
    error DepositTooSmall();
    error StrategyDepositFailed();

    /// @notice USDC token address used as the base asset
    IERC20 public immutable USDC;
    /// @notice WETH token address used for ETH exposure
    IERC20 public immutable WETH;

    /// @notice position manager contract for delta calculations
    IPositionManager public positionManager;
    /// @notice strategy for managing spot ETH positions
    IStrategy public spotStrategy;
    /// @notice strategy for managing perpetual positions
    IStrategy public perpStrategy;

    /// @notice precision constant for calculations (18 decimals)
    uint256 public constant PRECISION = 1e18;
    /// @notice maximum allowed delta tolerance in basis points (10%)
    uint256 public constant MAX_DELTA_TOLERANCE = 1000;
    /// @notice minimum deposit amount (1 USDC to prevent dust)
    uint256 public constant MIN_DEPOSIT = 1e6;

    /// @notice emergency pause state
    bool public paused;

    modifier whenNotPaused() {
        if (paused) revert VaultPaused();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != address(positionManager)) revert NotPositionManager();
        _;
    }

    /**
     * @notice constructs the market neutral vault
     * @param _usdc address of the USDC token contract
     * @param _weth address of the WETH token contract
     * @param _owner address of the vault owner
     */
    constructor(address _usdc, address _weth, address _owner) ERC20("Market Neutral Vault", "MNV", 18) Owned(_owner) {
        USDC = IERC20(_usdc);
        WETH = IERC20(_weth);
    }

    /**
     * @notice sets the position manager contract
     * @param _positionManager address of the position manager contract
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert ZeroAddress();
        positionManager = IPositionManager(_positionManager);
    }

    /**
     * @notice sets the spot strategy contract
     * @param _spotStrategy address of the spot strategy contract
     */
    function setSpotStrategy(address _spotStrategy) external onlyOwner {
        if (_spotStrategy == address(0)) revert ZeroAddress();
        spotStrategy = IStrategy(_spotStrategy);
    }

    /**
     * @notice sets the perpetual strategy contract
     * @param _perpStrategy address of the perpetual strategy contract
     */
    function setPerpStrategy(address _perpStrategy) external onlyOwner {
        if (_perpStrategy == address(0)) revert ZeroAddress();
        perpStrategy = IStrategy(_perpStrategy);
    }

    /**
     * @notice deposits USDC assets into the vault and mints shares
     * @param assets amount of USDC to deposit
     * @return shares amount of vault shares minted to depositor
     */
    function deposit(uint256 assets) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (assets < MIN_DEPOSIT) revert DepositTooSmall();
        if (address(spotStrategy) == address(0)) revert StrategyNotSet();
        if (address(perpStrategy) == address(0)) revert StrategyNotSet();

        // Calculate shares before transfer to use correct totalAssets
        shares = _calculateShares(assets);

        // Ensure we're minting at least 1 share
        if (shares == 0) revert ZeroAmount();

        // Transfer USDC from depositor
        SafeTransferLib.safeTransferFrom(ERC20(address(USDC)), msg.sender, address(this), assets);

        // Mint shares to depositor
        _mint(msg.sender, shares);

        // Deploy assets to strategies
        _deployAssets(assets);

        emit Deposit(msg.sender, assets, shares);
    }

    /**
     * @notice withdraws assets by burning vault shares
     * @param shares amount of vault shares to burn
     * @return assets amount of USDC withdrawn to user
     */
    function withdraw(uint256 shares) external nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();

        uint256 userBalance = balanceOf[msg.sender];
        if (shares > userBalance) revert InsufficientBalance();

        // Calculate assets before burning shares
        assets = previewWithdraw(shares);

        // Ensure we're actually withdrawing something
        if (assets == 0) revert ZeroAmount();

        // Burn shares first
        _burn(msg.sender, shares);

        // Then withdraw assets from strategies
        _withdrawAssets(assets);

        // Finally transfer assets to user
        SafeTransferLib.safeTransfer(ERC20(address(USDC)), msg.sender, assets);

        emit Withdraw(msg.sender, assets, shares);
    }

    /// @notice rebalances the vault to maintain delta neutrality
    function rebalance() external nonReentrant whenNotPaused {
        if (address(positionManager) == address(0)) revert PositionManagerNotSet();
        if (!positionManager.isRebalanceNeeded()) revert RebalanceNotNeeded();

        int256 oldDelta = getCurrentDelta();
        _performRebalance();
        int256 newDelta = getCurrentDelta();

        emit Rebalance(oldDelta, newDelta);
    }

    /// @notice pauses all vault operations in case of emergency
    function emergencyPause() external onlyOwner {
        paused = true;
        emit EmergencyPause(true);
    }

    /// @notice unpauses vault operations
    function emergencyUnpause() external onlyOwner {
        paused = false;
        emit EmergencyPause(false);
    }

    /**
     * @notice returns total assets under management across all strategies
     * @return total value of assets in USDC
     */
    function totalAssets() public view returns (uint256) {
        if (address(spotStrategy) == address(0) || address(perpStrategy) == address(0)) {
            return USDC.balanceOf(address(this));
        }

        return spotStrategy.totalAssets() + perpStrategy.totalAssets() + USDC.balanceOf(address(this));
    }

    /**
     * @notice previews shares received for a given deposit amount
     * @param assets amount of USDC to deposit
     * @return shares amount of vault shares that would be minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _calculateShares(assets);
    }

    /**
     * @notice previews assets received for withdrawing given shares
     * @param shares amount of vault shares to burn
     * @return assets amount of USDC that would be withdrawn
     */
    function previewWithdraw(uint256 shares) public view returns (uint256) {
        uint256 _totalSupply = totalSupply;

        if (_totalSupply == 0) {
            return 0;
        }

        // Use mulDivDown for precise calculation without overflow
        // assets = (shares * totalAssets) / totalSupply
        return shares.mulDivDown(totalAssets(), _totalSupply);
    }

    /**
     * @notice returns current delta exposure of the portfolio
     * @return delta current delta value (positive = net long, negative = net short)
     */
    function getCurrentDelta() public view returns (int256) {
        if (address(positionManager) == address(0)) return 0;
        return positionManager.getCurrentDelta();
    }

    /// @notice returns whether the vault is currently paused
    function isPaused() external view returns (bool) {
        return paused;
    }

    /// @notice returns vault shares balance for a given user
    function sharesOf(address user) external view returns (uint256) {
        return balanceOf[user];
    }

    /// @notice returns total supply of vault shares
    function totalShares() external view returns (uint256) {
        return totalSupply;
    }

    /// @dev calculates shares to mint based on deposit amount and current exchange rate
    function _calculateShares(uint256 assets) internal view returns (uint256) {
        uint256 _totalSupply = totalSupply;
        uint256 _totalAssets = totalAssets();

        // First depositor gets 1:1 shares
        if (_totalSupply == 0 || _totalAssets == 0) {
            return assets;
        }

        // Use mulDivDown for precise calculation without overflow
        // shares = (assets * totalSupply) / totalAssets
        return assets.mulDivDown(_totalSupply, _totalAssets);
    }

    /// @dev performs rebalancing logic to maintain delta neutrality
    function _performRebalance() internal {
        (uint256 spotAdjustment, uint256 perpAdjustment) = positionManager.calculateRebalanceAmounts();

        // TODO: implement actual rebalancing logic
        // this is a placeholder for now
        spotAdjustment;
        perpAdjustment;
    }

    /// @dev deploys deposited assets across spot and perpetual strategies
    function _deployAssets(uint256 assets) internal {
        // Calculate 50/50 split, ensuring all assets are allocated even for odd amounts
        uint256 spotAmount = assets / 2;
        uint256 perpAmount = assets - spotAmount; // Gets the remainder for odd amounts

        _deployToSpotStrategy(spotAmount);
        _deployToPerpStrategy(perpAmount);
        _updatePositionManager(spotAmount, perpAmount);
    }

    /// @dev deploys amount to spot strategy for ETH exposure
    function _deployToSpotStrategy(uint256 amount) internal {
        if (amount > 0) {
            SafeTransferLib.safeApprove(ERC20(address(USDC)), address(spotStrategy), amount);
            uint256 deposited = spotStrategy.deposit(amount);
            // Ensure the strategy accepted the full amount
            if (deposited != amount) revert StrategyDepositFailed();
        }
    }

    /// @dev deploys amount to perpetual strategy for short positions
    function _deployToPerpStrategy(uint256 amount) internal {
        if (amount > 0) {
            SafeTransferLib.safeApprove(ERC20(address(USDC)), address(perpStrategy), amount);
            uint256 deposited = perpStrategy.deposit(amount);
            // Ensure the strategy accepted the full amount
            if (deposited != amount) revert StrategyDepositFailed();
        }
    }

    /// @dev updates position manager with new position amounts
    function _updatePositionManager(uint256 spotAmount, uint256 perpAmount) internal {
        if (address(positionManager) != address(0)) {
            positionManager.updatePosition(spotAmount, perpAmount);
        }
    }

    /// @dev withdraws assets proportionally from strategies
    function _withdrawAssets(uint256 assets) internal {
        uint256 totalAssetsBefore = totalAssets();
        if (totalAssetsBefore == 0) return;

        _withdrawFromSpotStrategy(assets, totalAssetsBefore);
        _withdrawFromPerpStrategy(assets, totalAssetsBefore);
    }

    /// @dev withdraws proportional amount from spot strategy
    function _withdrawFromSpotStrategy(uint256 assets, uint256 totalAssetsBefore) internal {
        uint256 spotAssets = spotStrategy.totalAssets();
        if (spotAssets == 0) return;

        // Use higher precision calculation to minimize rounding errors
        uint256 spotWithdraw = (assets * spotAssets * PRECISION) / (totalAssetsBefore * PRECISION);
        if (spotWithdraw > 0) {
            uint256 withdrawn = spotStrategy.withdraw(spotWithdraw);
            // Ensure we received the expected amount
            if (withdrawn != spotWithdraw) revert InsufficientBalance();
        }
    }

    /// @dev withdraws proportional amount from perpetual strategy
    function _withdrawFromPerpStrategy(uint256 assets, uint256 totalAssetsBefore) internal {
        uint256 perpAssets = perpStrategy.totalAssets();
        if (perpAssets == 0) return;

        // Use higher precision calculation to minimize rounding errors
        uint256 perpWithdraw = (assets * perpAssets * PRECISION) / (totalAssetsBefore * PRECISION);
        if (perpWithdraw > 0) {
            uint256 withdrawn = perpStrategy.withdraw(perpWithdraw);
            // Ensure we received the expected amount
            if (withdrawn != perpWithdraw) revert InsufficientBalance();
        }
    }
}
