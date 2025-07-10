// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title strategy interface
 * @notice interface for spot and perpetual strategies
 */
interface IStrategy {
    function deposit(uint256 amount) external returns (uint256);
    
    function withdraw(uint256 amount) external returns (uint256);
    
    function totalAssets() external view returns (uint256);
}