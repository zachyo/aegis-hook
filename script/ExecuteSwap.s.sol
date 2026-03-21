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

contract ExecuteSwap is Script {
    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");

        vm.startBroadcast();

        // 1. Deploy test routers
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(IPoolManager(poolManager));

        address swapRouterAddress = address(swapRouter);
        address modifyLiquidityRouterAddress = address(modifyLiquidityRouter);

        // 1. Approve routers to spend tokens
        MockERC20(token0).approve(modifyLiquidityRouterAddress, type(uint256).max);
        MockERC20(token1).approve(modifyLiquidityRouterAddress, type(uint256).max);
        MockERC20(token0).approve(swapRouterAddress, type(uint256).max);
        MockERC20(token1).approve(swapRouterAddress, type(uint256).max);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });

        // 2. Add Liquidity
        // Adding liquidity across a wide range (-600 to +600 ticks)
        // console2.log("Adding liquidity to the pool...");
        // modifyLiquidityRouter.modifyLiquidity(
        //     poolKey,
        //     ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100_000 * 1e6, salt: 0}),
        //     new bytes(0)
        // );

        // 3. Execute a swap
        console2.log("Executing swap: 100 wei of TOKEN1 for TOKEN0");
        uint256 amountIn = 100;

        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: false,
                // casting to 'int256' is safe because amountIn is smaller than type(int256).max
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            new bytes(0)
        );

        console2.log("Swap completed successfully!");

        vm.stopBroadcast();
    }
}
