// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";

/// @title Multi-Swap Test Script
/// @notice Performs multiple swaps of varying sizes to trigger hook events:
///         - SwapExecuted (every swap)
///         - RebalanceNeeded (when deviation > 50 bps)
///         - Dynamic fee scaling
///         - Large-cap surcharge (orders ≥ $100k)
/// @dev Usage:
///   source .env && forge script script/MultiSwap.s.sol:MultiSwap \
///     --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast -vvv
contract MultiSwap is Script {
    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");

        StablecoinPegGuardianHook hook = StablecoinPegGuardianHook(hookAddress);

        vm.startBroadcast();

        // =====================================================================
        // 1. Deploy fresh test routers
        // =====================================================================
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        PoolModifyLiquidityTest modifyLiquidityRouter =
            new PoolModifyLiquidityTest(IPoolManager(poolManager));

        console2.log("=== Multi-Swap Test ===");
        console2.log("SwapRouter:", address(swapRouter));
        console2.log("ModifyLiquidityRouter:", address(modifyLiquidityRouter));

        // =====================================================================
        // 2. Approve routers
        // =====================================================================
        MockERC20(token0).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(token1).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(token0).approve(address(swapRouter), type(uint256).max);
        MockERC20(token1).approve(address(swapRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        // =====================================================================
        // 3. Add liquidity (wide range for testing)
        // =====================================================================
        console2.log("\n--- Adding Liquidity ---");
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: 100_000 * 1e6,
                salt: 0
            }),
            new bytes(0)
        );
        console2.log("Added 100k units of liquidity");

        // =====================================================================
        // 4. Log initial state
        // =====================================================================
        console2.log("\n--- Initial Hook State ---");
        console2.log("  PegPrice:", hook.pegPrice());
        console2.log("  CurrentPrice:", hook.currentPrice());
        console2.log("  DeviationBps:", hook.getDeviationBps());
        console2.log("  RebalanceCount:", hook.rebalanceCount());
        console2.log("  Paused:", hook.paused());

        // =====================================================================
        // 5. Swap 1 — Small swap (normal fee, no surcharge)
        // =====================================================================
        console2.log("\n--- Swap 1: Small swap (100 wei, token1 -> token0) ---");
        _doSwap(swapRouter, poolKey, false, 100);
        _logState(hook, "After Swap 1");

        // =====================================================================
        // 6. Swap 2 — Opposite direction
        // =====================================================================
        console2.log("\n--- Swap 2: Small swap (50 wei, token0 -> token1) ---");
        _doSwap(swapRouter, poolKey, true, 50);
        _logState(hook, "After Swap 2");

        // =====================================================================
        // 7. Simulate depeg and do another swap
        //    (This will trigger higher dynamic fees)
        // =====================================================================
        console2.log("\n--- Simulating depeg: setting price to 0.98e18 ---");
        hook.updatePrice(0.98e18);
        console2.log("  DeviationBps after depeg:", hook.getDeviationBps());

        console2.log("\n--- Swap 3: Swap during depeg (100 wei, token1 -> token0) ---");
        _doSwap(swapRouter, poolKey, false, 100);
        _logState(hook, "After Swap 3 (depeg active)");

        // =====================================================================
        // 8. Deeper depeg — should trigger RebalanceNeeded event
        // =====================================================================
        console2.log("\n--- Deepening depeg: setting price to 0.99e18 (100 bps deviation) ---");
        hook.updatePrice(0.99e18);
        console2.log("  DeviationBps:", hook.getDeviationBps());

        console2.log("\n--- Swap 4: Swap during deep depeg (200 wei, token0 -> token1) ---");
        _doSwap(swapRouter, poolKey, true, 200);
        _logState(hook, "After Swap 4 (deep depeg)");

        // =====================================================================
        // 9. Restore peg
        // =====================================================================
        console2.log("\n--- Restoring peg: setting price to 1.0e18 ---");
        hook.updatePrice(1e18);
        console2.log("  DeviationBps after restore:", hook.getDeviationBps());

        console2.log("\n--- Swap 5: Swap after peg restored (100 wei) ---");
        _doSwap(swapRouter, poolKey, false, 100);
        _logState(hook, "After Swap 5 (peg restored)");

        // =====================================================================
        // Summary
        // =====================================================================
        console2.log("\n=== Final State ===");
        console2.log("  PegPrice:", hook.pegPrice());
        console2.log("  CurrentPrice:", hook.currentPrice());
        console2.log("  DeviationBps:", hook.getDeviationBps());
        console2.log("  RebalanceCount:", hook.rebalanceCount());
        console2.log("  Total swaps executed: 5");

        vm.stopBroadcast();
    }

    function _doSwap(
        PoolSwapTest swapRouter,
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn
    ) internal {
        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                // casting to 'int256' is safe because amountIn is always small test values
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            new bytes(0)
        );
        console2.log("  Swap executed successfully");
    }

    function _logState(
        StablecoinPegGuardianHook hook,
        string memory label
    ) internal view {
        console2.log(string.concat("  [", label, "]"));
        console2.log("    CurrentPrice:", hook.currentPrice());
        console2.log("    DeviationBps:", hook.getDeviationBps());
        console2.log("    RebalanceCount:", hook.rebalanceCount());
    }
}
