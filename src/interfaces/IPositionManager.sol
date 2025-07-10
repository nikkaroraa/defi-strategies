// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title position manager interface
 * @notice interface for managing delta calculations and rebalancing logic
 */
interface IPositionManager {
    function isRebalanceNeeded() external view returns (bool);
    
    function getCurrentDelta() external view returns (int256);
    
    function calculateRebalanceAmounts() external view returns (uint256 spotAdjustment, uint256 perpAdjustment);
    
    function updatePosition(uint256 spotAmount, uint256 perpAmount) external;
}