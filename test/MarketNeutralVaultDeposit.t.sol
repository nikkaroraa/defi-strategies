// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {MarketNeutralVault} from "../src/MarketNeutralVault.sol";
import {IStrategy} from "../src/interfaces/IStrategy.sol";
import {MockAaveStrategy} from "../src/strategies/MockAaveStrategy.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

// Mock USDC token
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC", 6) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock WETH token  
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH", 18) {}
}

// Simple mock strategy
contract SimpleMockStrategy is IStrategy {
    IERC20 public immutable asset;
    uint256 public totalDeposited;
    
    constructor(address _asset) {
        asset = IERC20(_asset);
    }
    
    function deposit(uint256 amount) external returns (uint256) {
        asset.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
        return amount;
    }
    
    function withdraw(uint256 amount) external returns (uint256) {
        require(totalDeposited >= amount, "Insufficient balance");
        totalDeposited -= amount;
        asset.transfer(msg.sender, amount);
        return amount;
    }
    
    function totalAssets() external view returns (uint256) {
        return totalDeposited;
    }
}

// Mock Position Manager
contract MockPositionManager {
    uint256 public lastSpotAmount;
    uint256 public lastPerpAmount;
    
    function isRebalanceNeeded() external pure returns (bool) {
        return false;
    }
    
    function getCurrentDelta() external pure returns (int256) {
        return 0;
    }
    
    function calculateRebalanceAmounts() external pure returns (uint256, uint256) {
        return (0, 0);
    }
    
    function updatePosition(uint256 spotAmount, uint256 perpAmount) external {
        lastSpotAmount = spotAmount;
        lastPerpAmount = perpAmount;
    }
}

contract MarketNeutralVaultDepositTest is Test {
    MarketNeutralVault public vault;
    SimpleMockStrategy public spotStrategy;
    SimpleMockStrategy public perpStrategy;
    MockPositionManager public positionManager;
    MockUSDC public usdc;
    MockWETH public weth;
    
    address public owner = address(this);
    address public user = address(0x1234);
    
    function setUp() public {
        // Deploy tokens
        usdc = new MockUSDC();
        weth = new MockWETH();
        
        // Deploy vault
        vault = new MarketNeutralVault(address(usdc), address(weth), owner);
        
        // Deploy strategies
        spotStrategy = new SimpleMockStrategy(address(usdc));
        perpStrategy = new SimpleMockStrategy(address(usdc));
        
        // Setup vault strategies
        vault.setSpotStrategy(address(spotStrategy));
        vault.setPerpStrategy(address(perpStrategy));
        
        // Mint USDC to user
        usdc.mint(user, 1000 * 1e6); // 1000 USDC
    }
    
    function testDepositFirstUser() public {
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user);
        
        // Approve vault to spend USDC
        usdc.approve(address(vault), depositAmount);
        
        // Check initial state
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        
        // Deposit
        uint256 shares = vault.deposit(depositAmount);
        
        // First depositor should get 1:1 shares
        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user), depositAmount);
        assertEq(vault.totalSupply(), depositAmount);
        
        // Check that assets were deployed to strategies
        assertEq(spotStrategy.totalAssets(), depositAmount / 2);
        assertEq(perpStrategy.totalAssets(), depositAmount - (depositAmount / 2));
        
        vm.stopPrank();
    }
    
    function testDepositMinimumAmount() public {
        uint256 depositAmount = vault.MIN_DEPOSIT(); // 1 USDC
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        
        uint256 shares = vault.deposit(depositAmount);
        assertEq(shares, depositAmount);
        
        vm.stopPrank();
    }
    
    function testDepositBelowMinimumReverts() public {
        uint256 depositAmount = vault.MIN_DEPOSIT() - 1; // 0.999999 USDC
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        
        vm.expectRevert(MarketNeutralVault.DepositTooSmall.selector);
        vault.deposit(depositAmount);
        
        vm.stopPrank();
    }
    
    function testDepositZeroReverts() public {
        vm.startPrank(user);
        vm.expectRevert(MarketNeutralVault.ZeroAmount.selector);
        vault.deposit(0);
        vm.stopPrank();
    }
    
    function testDepositWithoutApprovalReverts() public {
        uint256 depositAmount = 100 * 1e6;
        
        vm.startPrank(user);
        // Don't approve
        vm.expectRevert(); // Will revert on transferFrom
        vault.deposit(depositAmount);
        vm.stopPrank();
    }
    
    function testSecondDeposit() public {
        // First deposit
        uint256 firstDeposit = 100 * 1e6;
        vm.startPrank(user);
        usdc.approve(address(vault), firstDeposit);
        vault.deposit(firstDeposit);
        vm.stopPrank();
        
        // Second user
        address user2 = address(0x5678);
        usdc.mint(user2, 1000 * 1e6);
        
        // Second deposit  
        uint256 secondDeposit = 50 * 1e6;
        vm.startPrank(user2);
        usdc.approve(address(vault), secondDeposit);
        
        // totalAssets should equal totalSupply for first depositor
        uint256 expectedShares = secondDeposit;
        uint256 shares = vault.deposit(secondDeposit);
        
        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(user2), expectedShares);
        
        vm.stopPrank();
    }
    
    function testDepositWithPositionManager() public {
        // Deploy and set position manager
        positionManager = new MockPositionManager();
        vault.setPositionManager(address(positionManager));
        
        uint256 depositAmount = 100 * 1e6; // 100 USDC
        
        vm.startPrank(user);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Check position manager was updated correctly
        assertEq(positionManager.lastSpotAmount(), depositAmount / 2);
        assertEq(positionManager.lastPerpAmount(), depositAmount - (depositAmount / 2));
    }
    
    function testDepositWithMockAaveStrategy() public {
        // Deploy vault with MockAaveStrategy
        MarketNeutralVault vaultWithAave = new MarketNeutralVault(address(usdc), address(weth), owner);
        MockAaveStrategy aaveStrategy = new MockAaveStrategy(address(usdc), address(vaultWithAave), owner);
        SimpleMockStrategy perpStrat = new SimpleMockStrategy(address(usdc));
        
        // Setup strategies
        vm.startPrank(owner);
        vaultWithAave.setSpotStrategy(address(aaveStrategy));
        vaultWithAave.setPerpStrategy(address(perpStrat));
        vm.stopPrank();
        
        // Deposit
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC
        
        vm.startPrank(user);
        usdc.approve(address(vaultWithAave), depositAmount);
        uint256 shares = vaultWithAave.deposit(depositAmount);
        vm.stopPrank();
        
        // Verify deployment
        assertEq(shares, depositAmount); // First depositor gets 1:1
        assertEq(aaveStrategy.totalAssets(), depositAmount / 2); // 500 USDC to spot
        assertEq(perpStrat.totalAssets(), depositAmount - (depositAmount / 2)); // 500 USDC to perp
        assertEq(vaultWithAave.totalAssets(), depositAmount);
        
        // Test yield accrual
        vm.warp(block.timestamp + 365 days);
        
        // Aave strategy should have accrued 5% yield on 500 USDC = 25 USDC
        uint256 expectedTotal = depositAmount + 25 * 1e6;
        assertApproxEqAbs(vaultWithAave.totalAssets(), expectedTotal, 1e6);
    }
}