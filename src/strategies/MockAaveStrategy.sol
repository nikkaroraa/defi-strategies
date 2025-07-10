// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

import {IStrategy} from "../interfaces/IStrategy.sol";

/**
 * @title mock aave strategy for testing
 * @author defi strategies team
 * @notice simplified strategy that simulates AAVE behavior without actual integration
 * @dev accepts USDC and tracks balances, simulating ETH exposure
 */
contract MockAaveStrategy is IStrategy, Owned {
    using SafeTransferLib for IERC20;
    
    error ZeroAmount();
    error InsufficientBalance();
    error OnlyVault();
    
    IERC20 public immutable USDC;
    address public vault;
    
    uint256 public totalDeposited;
    uint256 public constant MOCK_ETH_PRICE = 2000; // $2000 per ETH
    uint256 public constant USDC_DECIMALS = 1e6;
    uint256 public constant PRECISION = 1e18;
    
    // Simulate 5% APY
    uint256 public constant ANNUAL_YIELD_BPS = 500; // 5%
    uint256 public lastUpdateTime;
    
    event Deposited(uint256 usdcAmount);
    event Withdrawn(uint256 usdcAmount);
    
    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }
    
    constructor(
        address _usdc,
        address _vault,
        address _owner
    ) Owned(_owner) {
        USDC = IERC20(_usdc);
        vault = _vault;
        lastUpdateTime = block.timestamp;
    }
    
    /**
     * @notice deposits USDC into the strategy
     * @param amount amount of USDC to deposit
     * @return amount deposited
     */
    function deposit(uint256 amount) external onlyVault returns (uint256) {
        if (amount == 0) revert ZeroAmount();
        
        // Update yield before deposit
        _accrueYield();
        
        SafeTransferLib.safeTransferFrom(ERC20(address(USDC)), msg.sender, address(this), amount);
        totalDeposited += amount;
        
        emit Deposited(amount);
        return amount;
    }
    
    /**
     * @notice withdraws USDC from the strategy
     * @param amount amount of USDC to withdraw
     * @return amount withdrawn
     */
    function withdraw(uint256 amount) external onlyVault returns (uint256) {
        if (amount == 0) revert ZeroAmount();
        
        // Update yield before withdrawal
        _accrueYield();
        
        if (amount > totalDeposited) revert InsufficientBalance();
        
        totalDeposited -= amount;
        SafeTransferLib.safeTransfer(ERC20(address(USDC)), msg.sender, amount);
        
        emit Withdrawn(amount);
        return amount;
    }
    
    /**
     * @notice returns total assets under management
     * @return total USDC value including simulated yield
     */
    function totalAssets() external view returns (uint256) {
        return _calculateTotalWithYield();
    }
    
    /**
     * @notice simulates yield accrual
     */
    function _accrueYield() internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed > 0 && totalDeposited > 0) {
            // Simple interest calculation for mock
            uint256 yield = (totalDeposited * ANNUAL_YIELD_BPS * timeElapsed) / (10000 * 365 days);
            totalDeposited += yield;
            lastUpdateTime = block.timestamp;
        }
    }
    
    /**
     * @notice calculates total value including pending yield
     */
    function _calculateTotalWithYield() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0 || totalDeposited == 0) {
            return totalDeposited;
        }
        
        uint256 yield = (totalDeposited * ANNUAL_YIELD_BPS * timeElapsed) / (10000 * 365 days);
        return totalDeposited + yield;
    }
    
    /**
     * @notice updates vault address
     */
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
    
    /**
     * @notice emergency withdraw all funds to vault
     */
    function emergencyWithdraw() external onlyOwner returns (uint256) {
        _accrueYield();
        uint256 balance = totalDeposited;
        if (balance > 0) {
            totalDeposited = 0;
            SafeTransferLib.safeTransfer(ERC20(address(USDC)), vault, balance);
        }
        return balance;
    }
}