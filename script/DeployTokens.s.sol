// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract DeployTokens is Script {
    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;

        // Deploy Mock USDC (6 decimals)
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        // Mint 1 million USDC to deployer
        usdc.mint(deployer, 1_000_000 * 10**6);

        // Deploy Mock DAI (18 decimals)
        MockERC20 dai = new MockERC20("Mock DAI", "DAI", 18);
        // Mint 1 million DAI to deployer
        dai.mint(deployer, 1_000_000 * 10**18);

        vm.stopBroadcast();

        console2.log("=== Mock Tokens Deployed ===");
        console2.log("USDC address:", address(usdc));
        console2.log("DAI address:", address(dai));
        console2.log("Minted 1,000,000 of each to:", deployer);
        console2.log("\nPLEASE UPDATE YOUR .env WITH THESE VARIABLES:");
        
        // Uniswap v4 pools require tokens to be sorted by address
        if (address(usdc) < address(dai)) {
            console2.log("TOKEN0=%s", address(usdc));
            console2.log("TOKEN1=%s", address(dai));
        } else {
            console2.log("TOKEN0=%s", address(dai));
            console2.log("TOKEN1=%s", address(usdc));
        }
    }
}
