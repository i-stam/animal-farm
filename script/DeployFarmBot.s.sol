// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {FarmBot} from "../src/FarmBot.sol";

contract DeployFarmBotScript is Script {
    FarmBot public farmBot;
    
    function setUp() public {}
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy FarmBot contract
        farmBot = new FarmBot();
        
        console.log("FarmBot deployed at:", address(farmBot));
        console.log("Owner:", farmBot.owner());
        console.log("Default swap amount:", farmBot.defaultSwapAmount());
        console.log("APR threshold:", farmBot.aprThreshold());
        
        // Get current USDC APR for reference
        uint256 currentRate = farmBot.getCurrentUSDCApr();
        uint256 currentApr = farmBot.rayToApr(currentRate);
        console.log("Current USDC APR (basis points):", currentApr);
        console.log("Current USDC APR (percentage):", currentApr / 100);
        console.log("Should execute:", farmBot.shouldExecute());
        
        vm.stopBroadcast();
        
        // Verification info
        console.log("\n=== Deployment Complete ===");
        console.log("To verify on Etherscan, run:");
        console.log("forge verify-contract", address(farmBot), "src/FarmBot.sol:FarmBot --chain-id 1");
    }
}