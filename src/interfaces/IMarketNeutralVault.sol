// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title market neutral vault interface
 * @notice interface for vault that maintains market neutral exposure
 */
interface IMarketNeutralVault {
    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 assets, uint256 shares);
    event Rebalance(int256 oldDelta, int256 newDelta);
    event EmergencyPause(bool paused);
    
    function deposit(uint256 assets) external returns (uint256 shares);
    
    function withdraw(uint256 shares) external returns (uint256 assets);
    
    function rebalance() external;
    
    function emergencyPause() external;
    
    function emergencyUnpause() external;
    
    function totalAssets() external view returns (uint256);
    
    function totalShares() external view returns (uint256);
    
    function sharesOf(address user) external view returns (uint256);
    
    function previewDeposit(uint256 assets) external view returns (uint256);
    
    function previewWithdraw(uint256 shares) external view returns (uint256);
    
    function getCurrentDelta() external view returns (int256);
    
    function isPaused() external view returns (bool);
}