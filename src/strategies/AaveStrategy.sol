// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

import {IStrategy} from "../interfaces/IStrategy.sol";
import {IAaveV3Pool, IAToken} from "../interfaces/IAaveV3Pool.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/**
 * @title aave strategy
 * @author defi strategies team
 * @notice strategy that supplies assets to AAVE for yield generation
 * @dev handles conversion from USDC to WETH and supplies to AAVE lending pool
 */
contract AaveStrategy is IStrategy, Owned {
    using SafeTransferLib for IERC20;
    
    error ZeroAmount();
    error InsufficientBalance();
    error OnlyVault();
    error InsufficientETH();
    
    IERC20 public immutable USDC;
    IWETH public immutable WETH;
    IAaveV3Pool public immutable aavePool;
    IAToken public immutable aWETH;
    
    address public vault;
    
    uint256 public constant PRECISION = 1e18;
    
    event Deposited(uint256 usdcAmount, uint256 wethAmount, uint256 aWethReceived);
    event Withdrawn(uint256 aWethAmount, uint256 wethAmount, uint256 usdcAmount);
    event Harvested(uint256 rewards);
    
    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }
    
    /**
     * @notice constructs the AAVE strategy
     * @param _usdc address of the USDC token contract
     * @param _weth address of the WETH token contract
     * @param _aavePool address of the AAVE V3 pool contract
     * @param _aWeth address of the aWETH token contract
     * @param _vault address of the vault contract
     * @param _owner address of the strategy owner
     */
    constructor(
        address _usdc,
        address _weth,
        address _aavePool,
        address _aWeth,
        address _vault,
        address _owner
    ) Owned(_owner) {
        USDC = IERC20(_usdc);
        WETH = IWETH(_weth);
        aavePool = IAaveV3Pool(_aavePool);
        aWETH = IAToken(_aWeth);
        vault = _vault;
    }
    
    /**
     * @notice deposits USDC into the strategy and supplies WETH to AAVE
     * @param amount amount of USDC to deposit
     * @return shares amount of aWETH tokens received
     */
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        
        SafeTransferLib.safeTransferFrom(ERC20(address(USDC)), msg.sender, address(this), amount);
        
        uint256 wethAmount = _convertUsdcToWeth(amount);
        _supplyToAave(wethAmount);
        
        shares = aWETH.balanceOf(address(this));
        emit Deposited(amount, wethAmount, shares);
    }
    
    /**
     * @notice withdraws USDC by burning aWETH shares
     * @param shares amount of aWETH shares to burn
     * @return amount amount of USDC withdrawn to vault
     */
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        if (shares > aWETH.balanceOf(address(this))) revert InsufficientBalance();
        
        uint256 wethAmount = shares; // 1:1 ratio initially
        uint256 actualWethReceived = aavePool.withdraw(address(WETH), wethAmount, address(this));
        
        amount = _convertWethToUsdc(actualWethReceived);
        SafeTransferLib.safeTransfer(ERC20(address(USDC)), msg.sender, amount);
        
        emit Withdrawn(shares, actualWethReceived, amount);
    }
    
    /// @notice returns current balance of aWETH tokens held by strategy
    function balanceOf() external view returns (uint256) {
        return aWETH.balanceOf(address(this));
    }
    
    /// @notice returns total assets under management in USDC terms
    function totalAssets() external view returns (uint256) {
        uint256 aWethBalance = aWETH.balanceOf(address(this));
        if (aWethBalance == 0) return 0;
        
        // convert aWETH balance to USDC value
        return _convertWethToUsdcView(aWethBalance);
    }
    
    /// @notice returns the base asset address (USDC)
    function asset() external view returns (address) {
        return address(USDC);
    }
    
    /// @notice returns maximum deposit amount (unlimited)
    function maxDeposit() external pure returns (uint256) {
        return type(uint256).max;
    }
    
    /// @notice returns maximum withdrawable amount
    function maxWithdraw() external view returns (uint256) {
        return aWETH.balanceOf(address(this));
    }
    
    /// @notice harvests any additional rewards from AAVE
    function harvest() external onlyVault returns (uint256 harvested) {
        // AAVE rewards are automatically compounded in aTokens
        // this function could claim additional rewards if available
        harvested = 0;
        emit Harvested(harvested);
    }
    
    /// @notice emergency withdraw of all assets to vault (owner only)
    function emergencyWithdraw() external onlyOwner returns (uint256 amount) {
        uint256 aWethBalance = aWETH.balanceOf(address(this));
        if (aWethBalance == 0) return 0;
        
        uint256 wethReceived = aavePool.withdraw(address(WETH), aWethBalance, address(this));
        amount = _convertWethToUsdc(wethReceived);
        SafeTransferLib.safeTransfer(ERC20(address(USDC)), vault, amount);
    }
    
    /// @notice updates vault address (owner only)
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
    
    /// @dev supplies WETH to AAVE lending pool
    function _supplyToAave(uint256 wethAmount) internal {
        WETH.approve(address(aavePool), wethAmount);
        aavePool.supply(address(WETH), wethAmount, address(this), 0);
    }
    
    /// @dev converts USDC to WETH using mock exchange rate
    function _convertUsdcToWeth(uint256 usdcAmount) internal returns (uint256) {
        // simplified conversion - in reality would use uniswap or other DEX
        // for now, assume 1 USDC = 1/2000 WETH (ETH at $2000)
        uint256 wethAmount = (usdcAmount * 1e18) / (2000 * 1e6); // USDC has 6 decimals
        
        // mock conversion by minting WETH
        // in reality, this would be a DEX swap
        if (address(this).balance < wethAmount) revert InsufficientETH();
        WETH.deposit{value: wethAmount}();
        
        return wethAmount;
    }
    
    /// @dev converts WETH to USDC using mock exchange rate
    function _convertWethToUsdc(uint256 wethAmount) internal returns (uint256) {
        // simplified conversion - in reality would use uniswap or other DEX
        // for now, assume 1 WETH = 2000 USDC
        uint256 usdcAmount = (wethAmount * 2000 * 1e6) / 1e18; // USDC has 6 decimals
        
        // mock conversion
        // in reality, this would be a DEX swap
        return usdcAmount;
    }
    
    /// @dev view function for WETH to USDC conversion
    function _convertWethToUsdcView(uint256 wethAmount) internal pure returns (uint256) {
        // view function for conversion
        return (wethAmount * 2000 * 1e6) / 1e18;
    }
    
    // Allow contract to receive ETH for WETH operations
    receive() external payable {}
}