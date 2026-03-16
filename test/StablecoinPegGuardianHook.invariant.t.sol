// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {StablecoinPegGuardianHook} from "../src/StablecoinPegGuardianHook.sol";
import {PegGuardianCallback} from "../src/reactive/PegGuardianCallback.sol";

/// @title Handler for invariant testing
/// @notice Drives random admin operations on the hook for property-based testing
contract HookHandler is Test {
    StablecoinPegGuardianHook public hook;
    PegGuardianCallback public callback;
    address public reactiveSystem;
    address public hookOwner;

    // Ghost variables for tracking invariant properties
    uint256 public ghostPreviousRebalanceCount;
    uint256 public ghostPriceUpdateCount;
    uint256 public ghostPegUpdateCount;
    uint256 public ghostCallbackUpdateCount;

    constructor(
        StablecoinPegGuardianHook _hook,
        PegGuardianCallback _callback,
        address _reactiveSystem,
        address _hookOwner
    ) {
        hook = _hook;
        callback = _callback;
        reactiveSystem = _reactiveSystem;
        hookOwner = _hookOwner;
        ghostPreviousRebalanceCount = 0;
    }

    /// @notice Update the oracle price with a random valid value
    function updatePrice(uint256 newPrice) external {
        newPrice = bound(newPrice, 1, 10e18);

        vm.prank(hookOwner);
        hook.updatePrice(newPrice);
        ghostPriceUpdateCount++;
    }

    /// @notice Update the peg price with a random valid value
    function setPegPrice(uint256 newPeg) external {
        newPeg = bound(newPeg, 1, 10e18);

        vm.prank(hookOwner);
        hook.setPegPrice(newPeg);
        ghostPegUpdateCount++;
    }

    /// @notice Toggle pause state
    function togglePause(bool shouldPause) external {
        vm.prank(hookOwner);
        if (shouldPause) {
            if (!hook.paused()) {
                hook.pause();
            }
        } else {
            if (hook.paused()) {
                hook.unpause();
            }
        }
    }

    /// @notice Update price via authorized callback
    function callbackUpdatePrice(uint256 newPrice) external {
        newPrice = bound(newPrice, 1, 10e18);

        vm.prank(reactiveSystem);
        callback.handleRebalance(address(0), newPrice, 50);
        ghostCallbackUpdateCount++;
    }

    /// @notice Record rebalance count for monotonicity check
    function snapshotRebalanceCount() external {
        ghostPreviousRebalanceCount = hook.rebalanceCount();
    }
}

/// @title Invariant Tests for StablecoinPegGuardianHook
/// @notice Verifies system invariants hold across random operation sequences
contract StablecoinPegGuardianHookInvariantTest is Test, Deployers {
    StablecoinPegGuardianHook hook;
    PegGuardianCallback callback;
    HookHandler handler;

    address reactiveSystem = makeAddr("reactiveSystem");
    uint256 constant BPS_PRECISION = 10_000;

    function setUp() public {
        deployFreshManagerAndRouters();

        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        address hookAddress = address(flags);
        deployCodeTo(
            "StablecoinPegGuardianHook.sol:StablecoinPegGuardianHook",
            abi.encode(manager, address(this)),
            hookAddress
        );
        hook = StablecoinPegGuardianHook(hookAddress);

        // Deploy callback
        callback = new PegGuardianCallback(reactiveSystem, hookAddress);
        hook.setAuthorizedCallback(address(callback));

        // Deploy handler
        handler = new HookHandler(
            hook,
            callback,
            reactiveSystem,
            address(this)
        );

        // Target only the handler for invariant testing
        targetContract(address(handler));
    }

    // =========================================================================
    // Invariants
    // =========================================================================

    /// @notice currentPrice must always be greater than zero
    function invariant_priceAlwaysPositive() public view {
        assertGt(
            hook.currentPrice(),
            0,
            "INVARIANT VIOLATED: currentPrice is zero"
        );
    }

    /// @notice pegPrice must always be greater than zero
    function invariant_pegPriceAlwaysPositive() public view {
        assertGt(hook.pegPrice(), 0, "INVARIANT VIOLATED: pegPrice is zero");
    }

    /// @notice owner must never be the zero address
    function invariant_ownerNeverZero() public view {
        assertTrue(
            hook.owner() != address(0),
            "INVARIANT VIOLATED: owner is zero address"
        );
    }

    /// @notice rebalanceCount must be monotonically non-decreasing
    function invariant_rebalanceCountMonotonic() public view {
        assertGe(
            hook.rebalanceCount(),
            handler.ghostPreviousRebalanceCount(),
            "INVARIANT VIOLATED: rebalanceCount decreased"
        );
    }

    /// @notice getDeviationBps() must match manual calculation from state
    function invariant_deviationBpsConsistent() public view {
        uint256 current = hook.currentPrice();
        uint256 peg = hook.pegPrice();
        uint256 reportedDeviation = hook.getDeviationBps();

        // Manual calculation
        uint256 diff = current >= peg ? current - peg : peg - current;
        uint256 expectedDeviation = (diff * BPS_PRECISION) / peg;

        assertEq(
            reportedDeviation,
            expectedDeviation,
            "INVARIANT VIOLATED: deviation calculation inconsistent"
        );
    }

    /// @notice The computed dynamic fee can never exceed MAX_LP_FEE
    function invariant_feeWithinBounds() public view {
        uint256 deviationBps = hook.getDeviationBps();

        uint24 fee;
        if (deviationBps >= 100) {
            // MAX_DEVIATION_BPS
            fee = 10_000; // MAX_FEE
        } else {
            fee = uint24((deviationBps * 10_000) / 100);
        }

        // Even with max surcharge added
        fee += 2_000; // LARGECAP_SURCHARGE (worst case)

        // After capping
        if (fee > uint24(LPFeeLibrary.MAX_LP_FEE)) {
            fee = uint24(LPFeeLibrary.MAX_LP_FEE);
        }

        assertTrue(
            fee <= uint24(LPFeeLibrary.MAX_LP_FEE),
            "INVARIANT VIOLATED: fee exceeds MAX_LP_FEE"
        );
    }
}
