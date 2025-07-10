// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {MockAaveStrategy} from "../src/strategies/MockAaveStrategy.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC", 6) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAaveStrategyTest is Test {
    MockAaveStrategy public strategy;
    MockUSDC public usdc;
    
    address public vault = address(this);
    address public owner = address(this);
    
    function setUp() public {
        usdc = new MockUSDC();
        strategy = new MockAaveStrategy(address(usdc), vault, owner);
        
        // Mint USDC to vault
        usdc.mint(vault, 10000 * 1e6); // 10,000 USDC
    }
    
    function testDeposit() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC
        
        usdc.approve(address(strategy), depositAmount);
        uint256 returned = strategy.deposit(depositAmount);
        
        assertEq(returned, depositAmount);
        assertEq(strategy.totalAssets(), depositAmount);
        assertEq(usdc.balanceOf(address(strategy)), depositAmount);
    }
    
    function testWithdraw() public {
        uint256 depositAmount = 1000 * 1e6;
        
        // First deposit
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);
        
        // Then withdraw half
        uint256 withdrawAmount = 500 * 1e6;
        uint256 balanceBefore = usdc.balanceOf(vault);
        
        uint256 returned = strategy.withdraw(withdrawAmount);
        
        assertEq(returned, withdrawAmount);
        assertEq(strategy.totalAssets(), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(vault), balanceBefore + withdrawAmount);
    }
    
    function testYieldAccrual() public {
        uint256 depositAmount = 1000 * 1e6;
        
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);
        
        // Warp time by 1 year
        vm.warp(block.timestamp + 365 days);
        
        // Check that yield was accrued (5% APY)
        uint256 expectedTotal = depositAmount + (depositAmount * 500 / 10000); // 1050 USDC
        assertApproxEqAbs(strategy.totalAssets(), expectedTotal, 1e6); // Allow 1 USDC tolerance
    }
    
    function testOnlyVaultCanDeposit() public {
        address notVault = address(0x1234);
        
        vm.startPrank(notVault);
        vm.expectRevert(MockAaveStrategy.OnlyVault.selector);
        strategy.deposit(100 * 1e6);
        vm.stopPrank();
    }
    
    function testOnlyVaultCanWithdraw() public {
        address notVault = address(0x1234);
        
        vm.startPrank(notVault);
        vm.expectRevert(MockAaveStrategy.OnlyVault.selector);
        strategy.withdraw(100 * 1e6);
        vm.stopPrank();
    }
    
    function testCannotWithdrawMoreThanDeposited() public {
        uint256 depositAmount = 1000 * 1e6;
        
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);
        
        vm.expectRevert(MockAaveStrategy.InsufficientBalance.selector);
        strategy.withdraw(depositAmount + 1);
    }
    
    function testEmergencyWithdraw() public {
        uint256 depositAmount = 1000 * 1e6;
        
        usdc.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount);
        
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);
        uint256 withdrawn = strategy.emergencyWithdraw();
        
        assertEq(withdrawn, depositAmount);
        assertEq(strategy.totalAssets(), 0);
        assertEq(usdc.balanceOf(vault), vaultBalanceBefore + depositAmount);
    }
}