// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title price oracle interface
 * @notice interface for getting asset prices
 */
interface IPriceOracle {
    /**
     * @notice gets the price of an asset in USD
     * @param asset address of the asset
     * @return price price in USD with 8 decimals
     */
    function getAssetPrice(address asset) external view returns (uint256 price);
    
    /**
     * @notice gets the price of ETH in USD
     * @return price ETH price in USD with 8 decimals
     */
    function getEthPrice() external view returns (uint256 price);
}