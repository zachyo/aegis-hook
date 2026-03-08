// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "./BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

/// @title Stablecoin Peg Guardian Hook
/// @notice A Uniswap v4 hook that protects stablecoin pools with dynamic fees,
///         segmented order flow, and auto-rebalancing detection.
/// @dev Implements beforeSwap (dynamic fees), afterSwap (rebalance detection),
///      and beforeAddLiquidity (pause gate). Uses 2-step ownership transfer.
contract StablecoinPegGuardianHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using BalanceDeltaLibrary for BalanceDelta;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice Thrown when a non-owner calls an owner-only function
    error NotOwner();
    /// @notice Thrown when a non-pending-owner calls acceptOwnership
    error NotPendingOwner();
    /// @notice Thrown when the hook is paused
    error HookPaused();
    /// @notice Thrown when setting owner/pendingOwner to address(0)
    error ZeroAddress();
    /// @notice Thrown when providing an invalid price (zero)
    error InvalidPrice();
    /// @notice Thrown when an unauthorized address calls updatePriceFromCallback
    error NotAuthorizedCallback();

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a swap is executed through the hook
    /// @param poolId The pool that was swapped
    /// @param sender The address that initiated the swap
    /// @param fee The dynamic fee applied (in hundredths of a bip)
    /// @param deviationBps The peg deviation in basis points at time of swap
    event SwapExecuted(
        PoolId indexed poolId,
        address indexed sender,
        uint24 fee,
        uint256 deviationBps
    );

    /// @notice Emitted when peg deviation exceeds the critical threshold after a swap
    /// @param poolId The pool that triggered the rebalance signal
    /// @param deviationBps The peg deviation in basis points
    /// @param currentPrice The current oracle price
    event RebalanceNeeded(
        PoolId indexed poolId,
        uint256 deviationBps,
        uint256 currentPrice
    );

    /// @notice Emitted when liquidity is added to a guarded pool
    /// @param poolId The pool receiving liquidity
    /// @param sender The liquidity provider
    event LiquidityAdded(PoolId indexed poolId, address indexed sender);

    /// @notice Emitted when the oracle price is updated
    /// @param oldPrice The previous oracle price
    /// @param newPrice The new oracle price
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    /// @notice Emitted when the target peg price is updated
    /// @param oldPeg The previous peg price
    /// @param newPeg The new peg price
    event PegPriceUpdated(uint256 oldPeg, uint256 newPeg);

    /// @notice Emitted when the hook is paused
    /// @param account The address that paused the hook
    event Paused(address account);

    /// @notice Emitted when the hook is unpaused
    /// @param account The address that unpaused the hook
    event Unpaused(address account);

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner The previous owner
    /// @param newOwner The new owner
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /// @notice Emitted when a new pending owner is set
    /// @param pendingOwner The address of the pending owner
    event OwnershipTransferStarted(address indexed pendingOwner);

    /// @notice Emitted when a cross-chain callback updates the price
    /// @param oldPrice The previous price
    /// @param newPrice The new price from the callback
    /// @param caller The callback contract that triggered the update
    event CallbackPriceUpdated(
        uint256 oldPrice,
        uint256 newPrice,
        address caller
    );

    /// @notice Emitted when the authorized callback address is changed
    /// @param oldCallback The previous callback address
    /// @param newCallback The new callback address
    event AuthorizedCallbackUpdated(address oldCallback, address newCallback);

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Precision for price calculations (1e18 = $1.00)
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Retail order threshold ($10,000 in 18-decimal)
    uint256 public constant RETAIL_THRESHOLD = 10_000e18;

    /// @notice Large-cap order threshold ($100,000 in 18-decimal)
    uint256 public constant LARGECAP_THRESHOLD = 100_000e18;

    /// @notice Maximum dynamic fee: 100 bps (1%) = 10_000 in v4 hundredths-of-bip units
    uint24 public constant MAX_FEE = 10_000;

    /// @notice Large-cap surcharge: 20 bps = 2_000 in v4 hundredths-of-bip units
    uint24 public constant LARGECAP_SURCHARGE = 2_000;

    /// @notice Critical deviation threshold for rebalance signal: 50 bps (0.5%)
    uint256 public constant CRITICAL_DEVIATION_BPS = 50;

    /// @notice Maximum deviation for fee scaling: 100 bps (1%)
    uint256 public constant MAX_DEVIATION_BPS = 100;

    /// @notice Basis point precision
    uint256 private constant BPS_PRECISION = 10_000;

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Current contract owner
    address public owner;

    /// @notice Pending owner for 2-step transfer
    address public pendingOwner;

    /// @notice Whether the hook is paused
    bool public paused;

    /// @notice Target peg price in 18-decimal (1e18 = $1.00)
    uint256 public pegPrice;

    /// @notice Current oracle price in 18-decimal
    uint256 public currentPrice;

    /// @notice Counter for rebalance signals emitted
    uint256 public rebalanceCount;

    /// @notice Authorized callback contract for cross-chain price updates
    address public authorizedCallback;

    // =========================================================================
    // Modifiers
    // =========================================================================

    /// @notice Restricts function to the contract owner
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /// @notice Reverts if the hook is paused
    modifier whenNotPaused() {
        _checkNotPaused();
        _;
    }

    function _checkOwner() internal view {
        if (msg.sender != owner) revert NotOwner();
    }

    function _checkNotPaused() internal view {
        if (paused) revert HookPaused();
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @notice Deploys the hook and sets initial owner + peg price
    /// @param _poolManager The Uniswap v4 PoolManager
    /// @param _owner The initial owner of the hook
    constructor(
        IPoolManager _poolManager,
        address _owner
    ) BaseHook(_poolManager) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        pegPrice = PRICE_PRECISION; // default peg = $1.00
        currentPrice = PRICE_PRECISION; // assume on-peg at start
        emit OwnershipTransferred(address(0), _owner);
    }

    // =========================================================================
    // Hook Permissions
    // =========================================================================

    /// @inheritdoc BaseHook
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // =========================================================================
    // Hook Implementations
    // =========================================================================

    /// @notice Gate liquidity additions when paused and emit tracking event
    /// @dev Called by PoolManager before liquidity is added
    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override whenNotPaused returns (bytes4) {
        emit LiquidityAdded(key.toId(), sender);
        return BaseHook.beforeAddLiquidity.selector;
    }

    /// @notice Calculate and apply dynamic fee based on peg deviation + order segmentation
    /// @dev Fee scales linearly from 0 to MAX_FEE as deviation goes from 0% to 1%.
    ///      Large-cap orders (>$100k) receive an additional surcharge.
    ///      The fee is returned with OVERRIDE_FEE_FLAG so the PoolManager applies it.
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    )
        internal
        override
        whenNotPaused
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Calculate peg deviation in basis points
        uint256 deviationBps = _calculateDeviationBps();

        // Calculate dynamic fee: linear scale from 0 to MAX_FEE over 0 to MAX_DEVIATION_BPS
        uint24 fee;
        if (deviationBps >= MAX_DEVIATION_BPS) {
            fee = MAX_FEE;
        } else {
            // casting to uint24 is safe because result <= MAX_FEE (10_000) which fits in uint24
            // forge-lint: disable-next-line(unsafe-typecast)
            fee = uint24((deviationBps * MAX_FEE) / MAX_DEVIATION_BPS);
        }

        // Segmented order flow: large-cap surcharge
        uint256 swapAmount = params.amountSpecified < 0
            ? uint256(-int256(params.amountSpecified))
            : uint256(int256(params.amountSpecified));

        if (swapAmount >= LARGECAP_THRESHOLD) {
            fee += LARGECAP_SURCHARGE;
        }

        // Cap fee at LPFeeLibrary.MAX_LP_FEE to stay valid
        if (fee > LPFeeLibrary.MAX_LP_FEE) {
            fee = uint24(LPFeeLibrary.MAX_LP_FEE);
        }

        // Set the override flag so PoolManager uses this fee
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        // Emit swap event (poolId calculated here for gas, can be optimized later)
        emit SwapExecuted(key.toId(), tx.origin, fee, deviationBps);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeWithFlag
        );
    }

    /// @notice Post-swap monitoring: detect critical peg deviations and signal rebalance
    /// @dev Emits RebalanceNeeded when deviation exceeds CRITICAL_DEVIATION_BPS.
    ///      Phase 3 will replace this with Reactive cross-chain callbacks.
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        uint256 deviationBps = _calculateDeviationBps();

        if (deviationBps >= CRITICAL_DEVIATION_BPS) {
            rebalanceCount++;
            emit RebalanceNeeded(key.toId(), deviationBps, currentPrice);
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Update the current oracle price
    /// @param newPrice The new price in 18-decimal precision
    function updatePrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0) revert InvalidPrice();
        uint256 oldPrice = currentPrice;
        currentPrice = newPrice;
        emit PriceUpdated(oldPrice, newPrice);
    }

    /// @notice Update the target peg price
    /// @param newPeg The new target peg in 18-decimal precision
    function setPegPrice(uint256 newPeg) external onlyOwner {
        if (newPeg == 0) revert InvalidPrice();
        uint256 oldPeg = pegPrice;
        pegPrice = newPeg;
        emit PegPriceUpdated(oldPeg, newPeg);
    }

    /// @notice Pause the hook, blocking all swaps and liquidity additions
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the hook, resuming normal operation
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Start 2-step ownership transfer
    /// @param newOwner The address to transfer ownership to
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(newOwner);
    }

    /// @notice Accept pending ownership transfer
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    /// @notice Set the authorized callback contract for cross-chain price updates
    /// @param _callback Address of the PegGuardianCallback contract
    function setAuthorizedCallback(address _callback) external onlyOwner {
        address old = authorizedCallback;
        authorizedCallback = _callback;
        emit AuthorizedCallbackUpdated(old, _callback);
    }

    /// @notice Update the price from an authorized cross-chain callback
    /// @dev Only callable by the authorizedCallback contract
    /// @param newPrice The new price from the cross-chain oracle
    function updatePriceFromCallback(uint256 newPrice) external {
        if (msg.sender != authorizedCallback) revert NotAuthorizedCallback();
        if (newPrice == 0) revert InvalidPrice();
        uint256 oldPrice = currentPrice;
        currentPrice = newPrice;
        emit CallbackPriceUpdated(oldPrice, newPrice, msg.sender);
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /// @notice Calculate the absolute peg deviation in basis points
    /// @return deviationBps The deviation from peg in basis points (100 = 1%)
    function _calculateDeviationBps() internal view returns (uint256) {
        if (pegPrice == 0) return 0;

        uint256 diff;
        if (currentPrice >= pegPrice) {
            diff = currentPrice - pegPrice;
        } else {
            diff = pegPrice - currentPrice;
        }

        // deviation in bps = (diff / pegPrice) * 10_000
        return (diff * BPS_PRECISION) / pegPrice;
    }

    /// @notice Public view for current peg deviation (convenience for frontends/monitoring)
    /// @return deviationBps The current deviation from peg in basis points
    function getDeviationBps() external view returns (uint256) {
        return _calculateDeviationBps();
    }
}
