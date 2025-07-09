// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {ReentrancyGuard} from "lib/solmate/src/utils/ReentrancyGuard.sol";

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

    error ZeroAmount();
    error StrategyNotSet();
    error InsufficientBalance();
    error VaultPaused();
    error NotPositionManager();
    error RebalanceNotNeeded();
    error PositionManagerNotSet();

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
        positionManager = IPositionManager(_positionManager);
    }

    /**
     * @notice sets the spot strategy contract
     * @param _spotStrategy address of the spot strategy contract
     */
    function setSpotStrategy(address _spotStrategy) external onlyOwner {
        spotStrategy = IStrategy(_spotStrategy);
    }

    /**
     * @notice sets the perpetual strategy contract
     * @param _perpStrategy address of the perpetual strategy contract
     */
    function setPerpStrategy(address _perpStrategy) external onlyOwner {
        perpStrategy = IStrategy(_perpStrategy);
    }

    /**
     * @notice deposits USDC assets into the vault and mints shares
     * @param assets amount of USDC to deposit
     * @return shares amount of vault shares minted to depositor
     */
    function deposit(uint256 assets) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (address(spotStrategy) == address(0)) revert StrategyNotSet();
        if (address(perpStrategy) == address(0)) revert StrategyNotSet();

        SafeTransferLib.safeTransferFrom(ERC20(address(USDC)), msg.sender, address(this), assets);

        shares = _calculateShares(assets);
        _mint(msg.sender, shares);
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
        if (shares > balanceOf[msg.sender]) revert InsufficientBalance();

        assets = previewWithdraw(shares);
        _burn(msg.sender, shares);
        _withdrawAssets(assets);

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
    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 totalAssetsBefore = totalAssets();
        return totalAssetsBefore == 0 ? assets : (assets * totalSupply) / totalAssetsBefore;
    }

    /**
     * @notice previews assets received for withdrawing given shares
     * @param shares amount of vault shares to burn
     * @return assets amount of USDC that would be withdrawn
     */
    function previewWithdraw(uint256 shares) public view returns (uint256) {
        return totalSupply == 0 ? 0 : (shares * totalAssets()) / totalSupply;
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
    function isPaused() public view returns (bool) {
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
        uint256 totalAssetsBefore = totalAssets();
        return totalAssetsBefore == 0 ? assets : (assets * totalSupply) / totalAssetsBefore;
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
        uint256 spotAmount = assets / 2;
        uint256 perpAmount = assets - spotAmount;

        _deployToSpotStrategy(spotAmount);
        _deployToPerpStrategy(perpAmount);
        _updatePositionManager(spotAmount, perpAmount);
    }

    /// @dev deploys amount to spot strategy for ETH exposure
    function _deployToSpotStrategy(uint256 amount) internal {
        if (amount > 0) {
            USDC.approve(address(spotStrategy), amount);
            spotStrategy.deposit(amount);
        }
    }

    /// @dev deploys amount to perpetual strategy for short positions
    function _deployToPerpStrategy(uint256 amount) internal {
        if (amount > 0) {
            USDC.approve(address(perpStrategy), amount);
            perpStrategy.deposit(amount);
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
        uint256 spotWithdraw = (assets * spotStrategy.totalAssets()) / totalAssetsBefore;
        if (spotWithdraw > 0) {
            spotStrategy.withdraw(spotWithdraw);
        }
    }

    /// @dev withdraws proportional amount from perpetual strategy
    function _withdrawFromPerpStrategy(uint256 assets, uint256 totalAssetsBefore) internal {
        uint256 perpWithdraw = (assets * perpStrategy.totalAssets()) / totalAssetsBefore;
        if (perpWithdraw > 0) {
            perpStrategy.withdraw(perpWithdraw);
        }
    }
}
