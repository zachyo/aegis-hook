the core "gray areas" or missing pieces that were overlooked in the current implementation:

1. The "Protective Swap" is Missing (Event-Only Rebalancing)
   PRD Requirement: "Auto-rebalancing & protective swaps via afterSwap + Reactive callbacks"
   Reality: The \_afterSwap hook correctly calculates deviation and emits a RebalanceNeeded event if it exceeds 50 bps. The Reactive Network successfully picks this up and triggers PegGuardianCallback on the destination chain. However, the callback only calls updatePriceFromCallback() on the destination hook to update the internal oracle price. It never actually executes a restorative buy/sell swap against the pool to fix the peg.
2. Segmented Order Flow Decimals Bug
   PRD Requirement: "Segmented order flow (retail < $10k vs. large-cap > $100k)"
   Reality: In \_beforeSwap, the code checks if swapAmount >= LARGECAP_THRESHOLD (which is hardcoded to 100_000e18). This assumes all tokens have 18 decimals. If this hook is attached to a USDC or USDT pool (which use 6 decimals), an order of $100,000 is represented as 100,000,000,000 (100k \* 1e6). Because this is vastly smaller than 100_000e18, the large-cap surcharge will never trigger for USDC/USDT pairs. Furthermore, it doesn't check which token is being specified in amountSpecified.
3. Oracle Freshness vs Execution
   PRD Requirement: "Cross-chain oracle subscription"
   Reality: The hook has updatePriceFromOracle() to pull Chainlink prices. However, there is no mechanism built into the hook (or a deployed keeper) that actively calls this function before swaps. If no one manually calls this, \_beforeSwap relies on a potentially stale currentPrice to calculate the peg deviation and dynamic fee.
4. Multisig Admin Controls
   PRD Requirement: "Emergency pause + admin controls (multisig)"
   Reality: The hook implements a solid 2-step ownership pattern (transferOwnership / acceptOwnership), and pause() is fully functional. However, the deployer is currently a single private key wallet (EOA). To fulfill the "multisig" requirement for production/hackathon judging, ownership would need to be formally transferred to a Gnosis Safe or similar multisig contract.
