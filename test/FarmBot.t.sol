// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {FarmBot} from "../src/FarmBot.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAaveV3Pool} from "../src/interfaces/IAaveV3Pool.sol";

contract FarmBotTest is Test {
    FarmBot public farmBot;
    
    address public constant USDC = 0xa0B86a33e964E4B31c895d03B7E6A2cE1d6F3c39;
    address public constant AAVE_V3_POOL = 0x87870BceD4D87a94a3DB5B2067b8daCF0e8cc06c;
    address public constant AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c; // aUSDC token
    
    address public owner;
    address public user;
    
    function setUp() public {
        // Fork mainnet at a specific block
        vm.createFork("https://eth-mainnet.alchemyapi.io/v2/demo", 18500000);
        vm.selectFork(0);
        
        owner = makeAddr("owner");
        user = makeAddr("user");
        
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        
        vm.prank(owner);
        farmBot = new FarmBot();
    }
    
    function testDeployment() public {
        assertEq(farmBot.owner(), owner);
        assertEq(farmBot.defaultSwapAmount(), 5 ether);
        assertEq(farmBot.aprThreshold(), 500); // 5%
    }
    
    function testGetCurrentUSDCApr() public {
        uint256 apr = farmBot.getCurrentUSDCApr();
        assertGt(apr, 0, "APR should be greater than 0");
        
        uint256 aprBasisPoints = farmBot.rayToApr(apr);
        console.log("Current USDC APR (basis points):", aprBasisPoints);
        console.log("Current USDC APR (percentage):", aprBasisPoints / 100);
    }
    
    function testRayToAprConversion() public {
        // Test ray conversion
        uint256 fivePercentRay = 50000000000000000000000000; // 5% in ray
        uint256 converted = farmBot.rayToApr(fivePercentRay);
        assertEq(converted, 500, "5% should convert to 500 basis points");
    }
    
    function testShouldExecute() public {
        // Get current APR and test logic
        uint256 currentRate = farmBot.getCurrentUSDCApr();
        uint256 currentApr = farmBot.rayToApr(currentRate);
        
        bool shouldExec = farmBot.shouldExecute();
        if (currentApr >= 500) {
            assertTrue(shouldExec, "Should execute when APR >= 5%");
        } else {
            assertFalse(shouldExec, "Should not execute when APR < 5%");
        }
    }
    
    function testForceExecute() public {
        uint256 ethAmount = 1 ether;
        uint256 minUsdcOut = 2000 * 1e6; // Expect at least 2000 USDC (conservative estimate)
        
        uint256 initialUsdcBalance = IERC20(USDC).balanceOf(address(farmBot));
        uint256 initialAUsdcBalance = IERC20(AUSDC).balanceOf(address(farmBot));
        
        vm.prank(owner);
        farmBot.forceExecute{value: ethAmount}(ethAmount, minUsdcOut);
        
        // Check that USDC was swapped and deposited (contract should have aUSDC now)
        uint256 finalUsdcBalance = IERC20(USDC).balanceOf(address(farmBot));
        uint256 finalAUsdcBalance = IERC20(AUSDC).balanceOf(address(farmBot));
        
        assertEq(finalUsdcBalance, initialUsdcBalance, "USDC should be 0 after deposit");
        assertGt(finalAUsdcBalance, initialAUsdcBalance, "aUSDC balance should increase");
        
        console.log("aUSDC received:", finalAUsdcBalance - initialAUsdcBalance);
    }
    
    function testExecuteIfProfitable() public {
        uint256 ethAmount = 1 ether;
        uint256 minUsdcOut = 2000 * 1e6;
        
        // First, check if current APR meets threshold
        bool shouldExec = farmBot.shouldExecute();
        
        vm.prank(owner);
        if (shouldExec) {
            // Should succeed
            farmBot.executeIfProfitable{value: ethAmount}(ethAmount, minUsdcOut);
            
            uint256 aUsdcBalance = IERC20(AUSDC).balanceOf(address(farmBot));
            assertGt(aUsdcBalance, 0, "Should have aUSDC after execution");
        } else {
            // Should revert
            vm.expectRevert("APR threshold not met");
            farmBot.executeIfProfitable{value: ethAmount}(ethAmount, minUsdcOut);
        }
    }
    
    function testUpdateConfig() public {
        uint256 newSwapAmount = 10 ether;
        uint256 newAprThreshold = 300; // 3%
        
        vm.prank(owner);
        farmBot.updateConfig(newSwapAmount, newAprThreshold);
        
        assertEq(farmBot.defaultSwapAmount(), newSwapAmount);
        assertEq(farmBot.aprThreshold(), newAprThreshold);
    }
    
    function testUpdateConfigOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        farmBot.updateConfig(10 ether, 300);
    }
    
    function testTransferOwnership() public {
        vm.prank(owner);
        farmBot.transferOwnership(user);
        
        assertEq(farmBot.owner(), user);
    }
    
    function testTransferOwnershipOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        farmBot.transferOwnership(user);
    }
    
    function testEmergencyWithdrawETH() public {
        // Send some ETH to contract
        vm.deal(address(farmBot), 5 ether);
        
        uint256 initialBalance = owner.balance;
        
        vm.prank(owner);
        farmBot.emergencyWithdraw(address(0), 2 ether);
        
        assertEq(owner.balance, initialBalance + 2 ether);
        assertEq(address(farmBot).balance, 3 ether);
    }
    
    function testEmergencyWithdrawERC20() public {
        // First do a swap to get some aUSDC
        vm.prank(owner);
        farmBot.forceExecute{value: 1 ether}(1 ether, 2000 * 1e6);
        
        uint256 aUsdcBalance = IERC20(AUSDC).balanceOf(address(farmBot));
        assertGt(aUsdcBalance, 0, "Should have aUSDC");
        
        uint256 initialOwnerBalance = IERC20(AUSDC).balanceOf(owner);
        
        vm.prank(owner);
        farmBot.emergencyWithdraw(AUSDC, aUsdcBalance / 2);
        
        uint256 finalOwnerBalance = IERC20(AUSDC).balanceOf(owner);
        assertEq(finalOwnerBalance, initialOwnerBalance + aUsdcBalance / 2);
    }
    
    function testGetStatus() public {
        (uint256 currentApr, bool shouldExec, uint256 ethBalance, uint256 usdcBalance) = farmBot.getStatus();
        
        assertGt(currentApr, 0, "APR should be > 0");
        assertEq(ethBalance, 0, "ETH balance should be 0 initially");
        assertEq(usdcBalance, 0, "USDC balance should be 0 initially");
        
        console.log("Status - APR:", currentApr, "Should Execute:", shouldExec);
    }
    
    function testReceiveETH() public {
        uint256 initialBalance = address(farmBot).balance;
        
        (bool success, ) = address(farmBot).call{value: 1 ether}("");
        assertTrue(success, "Should accept ETH");
        
        assertEq(address(farmBot).balance, initialBalance + 1 ether);
    }
    
    function testFailInsufficientETH() public {
        vm.prank(owner);
        vm.expectRevert("Insufficient ETH sent");
        farmBot.forceExecute{value: 0.5 ether}(1 ether, 2000 * 1e6);
    }
    
    function testRefundExcessETH() public {
        uint256 initialBalance = owner.balance;
        
        vm.prank(owner);
        farmBot.forceExecute{value: 2 ether}(1 ether, 2000 * 1e6);
        
        // Should refund 1 ether
        assertEq(owner.balance, initialBalance - 1 ether);
    }
}