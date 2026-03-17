// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";
import {HookMiner} from "./HookMiner.sol";

/// @title Deploy Script for StablecoinPegGuardianHook
/// @notice Deploys the hook via CREATE2 with correct flag-encoded address
///         and initializes a stablecoin pool with DYNAMIC_FEE_FLAG
/// @dev Usage:
///   forge script script/Deploy.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast \
///     --verify \
///     --etherscan-api-key $ETHERSCAN_API_KEY \
///     -vvv
contract DeployHook is Script {
    // =========================================================================
    // Configuration — set via environment variables
    // =========================================================================

    function run() external {
        // Read environment config
        address poolManager = vm.envAddress("POOL_MANAGER");
        address deployer = vm.envAddress("DEPLOYER");

        // Optional: token addresses for pool initialization
        // If not set, only the hook is deployed (no pool init)
        address token0 = vm.envOr("TOKEN0", address(0));
        address token1 = vm.envOr("TOKEN1", address(0));

        console2.log("=== StablecoinPegGuardianHook Deployment ===");
        console2.log("PoolManager:", poolManager);
        console2.log("Deployer:", deployer);

        vm.startBroadcast();

        // ---------------------------------------------------------------------
        // Step 1: Mine salt for correct hook address flags
        // ---------------------------------------------------------------------
        uint160 flags = uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(poolManager, deployer);
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        (address hookAddress, bytes32 salt) =
            HookMiner.find(create2Deployer, flags, type(StablecoinPegGuardianHook).creationCode, constructorArgs);

        console2.log("Mined salt:", uint256(salt));
        console2.log("Hook address:", hookAddress);

        // ---------------------------------------------------------------------
        // Step 2: Deploy hook via CREATE2
        // ---------------------------------------------------------------------
        StablecoinPegGuardianHook hook = new StablecoinPegGuardianHook{salt: salt}(IPoolManager(poolManager), deployer);

        require(address(hook) == hookAddress, "Deploy: hook address mismatch");

        console2.log("Hook deployed at:", address(hook));
        console2.log("Owner:", hook.owner());

        // ---------------------------------------------------------------------
        // Step 3: Initialize pool (optional — requires token addresses)
        // ---------------------------------------------------------------------
        if (token0 != address(0) && token1 != address(0)) {
            // Ensure token0 < token1 (Uniswap v4 requirement)
            if (token0 > token1) {
                (token0, token1) = (token1, token0);
            }

            PoolKey memory poolKey = PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                tickSpacing: 60, // standard for stablecoins
                hooks: IHooks(address(hook))
            });

            // Initialize at 1:1 price (sqrtPriceX96 for 1.0)
            // sqrt(1) * 2^96 = 79228162514264337593543950336
            uint160 sqrtPriceX96 = 79228162514264337593543950336;

            IPoolManager(poolManager).initialize(poolKey, sqrtPriceX96);
            console2.log("Pool initialized with DYNAMIC_FEE_FLAG");
            console2.log("  Token0:", token0);
            console2.log("  Token1:", token1);
            console2.log("  TickSpacing: 60");
        } else {
            console2.log("Skipping pool init (set TOKEN0 and TOKEN1 env vars to initialize)");
        }

        // ---------------------------------------------------------------------
        // Step 4: Transfer ownership to Gnosis Safe (optional)
        // ---------------------------------------------------------------------
        address safeAddress = vm.envOr("SAFE_ADDRESS", address(0));
        if (safeAddress != address(0)) {
            hook.transferOwnership(safeAddress);
            console2.log("Ownership transfer initiated to Safe:", safeAddress);
            console2.log("  The Safe MUST call acceptOwnership() to finalize.");
        }

        vm.stopBroadcast();

        // Log summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Hook:", address(hook));
        console2.log("Owner:", hook.owner());
        console2.log("PendingOwner:", hook.pendingOwner());
        console2.log("PegPrice:", hook.pegPrice());
        console2.log("CurrentPrice:", hook.currentPrice());
    }
}
