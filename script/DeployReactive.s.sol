// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {PegMonitorReactive} from "../src/reactive/PegMonitorReactive.sol";
import {PegGuardianCallback} from "../src/reactive/PegGuardianCallback.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @title Deploy Script for Reactive Cross-Chain Contracts
/// @notice Two-step deployment:
///   1. Deploy PegGuardianCallback on destination chain (Sepolia)
///   2. Deploy PegMonitorReactive on Reactive Network (Kopli testnet)
///
/// @dev Step 1 — Deploy callback on Sepolia:
///   HOOK_ADDRESS=0x... forge script script/DeployReactive.s.sol:DeployCallback \
///     --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv
///
/// @dev Step 2 — Deploy reactive monitor on Kopli:
///   HOOK_ADDRESS=0x... CALLBACK_ADDRESS=0x... forge script script/DeployReactive.s.sol:DeployReactiveMonitor \
///     --rpc-url $REACTIVE_RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv

// =========================================================================
// Step 1: Deploy PegGuardianCallback on destination chain
// =========================================================================

contract DeployCallback is Script {
    function run() external {
        address hookAddress = vm.envAddress("HOOK_ADDRESS");

        // Reactive Network Callback Proxy on Sepolia
        // This is the address that actually relays cross-chain callbacks
        address callbackProxyAddress = vm.envOr("CALLBACK_PROXY_ADDRESS", address(0));

        // If not set, use a placeholder — must be updated before production
        if (callbackProxyAddress == address(0)) {
            callbackProxyAddress = vm.envAddress("DEPLOYER");
            console2.log(
                "WARNING: Using DEPLOYER as callback proxy. Set CALLBACK_PROXY_ADDRESS from https://dev.reactive.network/origins-and-destinations"
            );
        }

        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address poolManager = vm.envAddress("POOL_MANAGER");

        console2.log("=== PegGuardianCallback Deployment ===");
        console2.log("Hook address:", hookAddress);
        console2.log("Callback proxy:", callbackProxyAddress);

        vm.startBroadcast();

        // 1. Deploy test router for protective swaps
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));

        // 2. Compute pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        PegGuardianCallback callback =
            new PegGuardianCallback(callbackProxyAddress, hookAddress, address(swapRouter), poolKey);

        console2.log("Callback deployed at:", address(callback));
        console2.log("\nNext: Set this as authorized callback on the hook:");
        console2.log("  hook.setAuthorizedCallback(", address(callback), ")");

        vm.stopBroadcast();
    }
}

// =========================================================================
// Step 2: Deploy PegMonitorReactive on Reactive Network
// =========================================================================

contract DeployReactiveMonitor is Script {
    // Chain IDs
    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant KOPLI_CHAIN_ID = 5318008;
    uint256 constant LASNA_CHAIN_ID = 5318007;

    function run() external {
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address callbackAddress = vm.envAddress("CALLBACK_ADDRESS");

        // Allow overriding chain IDs for different deployments
        uint256 originChainId = vm.envOr("ORIGIN_CHAIN_ID", SEPOLIA_CHAIN_ID);
        uint256 destinationChainId = vm.envOr("DESTINATION_CHAIN_ID", SEPOLIA_CHAIN_ID);

        console2.log("=== PegMonitorReactive Deployment ===");
        console2.log("Origin chain:", originChainId);
        console2.log("Destination chain:", destinationChainId);
        console2.log("Hook address:", hookAddress);
        console2.log("Callback address:", callbackAddress);

        vm.startBroadcast();

        PegMonitorReactive monitor =
            new PegMonitorReactive{value: 0.02 ether}(originChainId, destinationChainId, hookAddress, callbackAddress);

        console2.log("\nReactive monitor deployed at:", address(monitor));
        console2.log("Callback count:", monitor.callbackCount());

        vm.stopBroadcast();

        console2.log("\n=== Deployment Complete ===");
        console2.log("Hook (origin):", hookAddress);
        console2.log("Callback (destination):", callbackAddress);
        console2.log("Monitor (Reactive):", address(monitor));
        console2.log("\n*** IMPORTANT ***");
        console2.log("Forge cannot simulate the Reactive system contract for subscriptions.");
        console2.log("You MUST manually subscribe to events by running the following command:");
        console2.log(
            string.concat(
                "cast send ",
                vm.toString(address(monitor)),
                " 'subscribeToEvents()' --rpc-url $REACTIVE_RPC_URL --private-key $PRIVATE_KEY"
            )
        );
    }
}
