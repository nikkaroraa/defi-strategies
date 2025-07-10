// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title AAVE V3 pool interface
 * @notice interface for interacting with AAVE V3 lending pool
 */
interface IAaveV3Pool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/**
 * @title AAVE aToken interface
 * @notice interface for AAVE interest bearing tokens
 */
interface IAToken {
    function balanceOf(address account) external view returns (uint256);
    
    function transfer(address to, uint256 amount) external returns (bool);
    
    function approve(address spender, uint256 amount) external returns (bool);
}