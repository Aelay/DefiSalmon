// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/DefiSalmon.sol";

contract DefiSalmonTest is Test {
    DefiSalmon public defiSalmon;
    address public user = address(0x123);
    
    function setUp() public {
        defiSalmon = new DefiSalmon();
    }
    
    function testDepositWithoutMultiplication() public {
        // Test that deposit doesn't multiply by decimals anymore
        vm.startPrank(user);
        
        // Mock USDT balance for user
        defiSalmon.mintTestUSDT(1000000); // 1 USDT with 6 decimals
        
        // Check initial balance
        uint256 initialBalance = defiSalmon.userDeposits(user, defiSalmon.USDT());
        assertEq(initialBalance, 1000000);
        
        vm.stopPrank();
    }
    
    function testBorrowLimits() public {
        vm.startPrank(user);
        
        // Give user some collateral
        defiSalmon.mintTestUSDT(1000000000); // 1000 USDT
        
        uint256 collateralValue = defiSalmon.getCollateralValue(user);
        assertGt(collateralValue, 0);
        
        uint256 maxBorrow = defiSalmon.getMaxBorrowAmount(user);
        assertGt(maxBorrow, 0);
        
        // Should be able to borrow up to 70% of collateral
        uint256 expectedMaxBorrow = (collateralValue * 70) / 100;
        assertEq(maxBorrow, expectedMaxBorrow);
        
        // Try to borrow within limit (should succeed)
        defiSalmon.borrow(maxBorrow);
        assertEq(defiSalmon.userBorrows(user), maxBorrow);
        
        // Try to borrow beyond limit (should fail)
        vm.expectRevert("Exceeds max LTV ratio");
        defiSalmon.borrow(1);
        
        vm.stopPrank();
    }
    
    function testHealthFactor() public {
        vm.startPrank(user);
        
        // Give user collateral
        defiSalmon.mintTestUSDT(1000000000); // 1000 USDT
        
        // Check health factor before borrowing (should be infinite)
        uint256 healthFactorBefore = defiSalmon.getHealthFactor(user);
        assertEq(healthFactorBefore, type(uint256).max);
        
        // Borrow some amount
        uint256 borrowAmount = 500000000; // 500 USDT
        defiSalmon.borrow(borrowAmount);
        
        // Check health factor after borrowing
        uint256 healthFactorAfter = defiSalmon.getHealthFactor(user);
        assertLt(healthFactorAfter, type(uint256).max);
        assertGt(healthFactorAfter, 100); // Should be > 1 (100 in basis points)
        
        vm.stopPrank();
    }
    
    function testETHPriceOracle() public {
        uint256 ethPrice = defiSalmon.getETHPrice();
        assertGt(ethPrice, 0, "ETH price should be positive");
        
        // Price should be reasonable (between $1000 and $10000)
        assertGt(ethPrice, 100000000000); // > $1000 * 1e8
        assertLt(ethPrice, 1000000000000); // < $10000 * 1e8
    }
}