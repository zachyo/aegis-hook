# Stablecoin Peg Guardian Hook — Demo Video Script (3 Minutes)

> **Format:** Screen share with voiceover. Pre-load all tabs/files before recording.
> **Tools:** Loom or OBS. Upload to YouTube or Loom for submission.

---

## Pre-Recording Setup Checklist

Before hitting record, have these ready:

1. **Browser tabs open:**
   - Frontend dashboard running locally (`npm run dev` in `frontend/`)
   - Sepolia Etherscan with your hook address: `0x67F3Bd11b7f80Dc867B60CB06a89f478F0f8C8c0`
   - (Optional) Architecture diagram from README

2. **VS Code/editor open with files:**
   - `src/StablecoinPegGuardianHook.sol` — scrolled to `_beforeSwap` function
   - `src/reactive/PegGuardianCallback.sol` — scrolled to `handleRebalance`
   - `src/reactive/PegMonitorReactive.sol`

3. **Terminal ready with:**
   - `cd ~/Documents/GitHub/WEB3/uniswap/stablecoin-peg`
   - `.env` sourced (`source .env`)
   - Test command ready: `forge test`

---

## Script

### [0:00 – 0:30] The Problem (Show slides or speak over architecture diagram)

> **[Show architecture diagram from README or a simple slide]**

"Hey everyone — I'm [Your Name], and this is **Stablecoin Peg Guardian Hook**, a Uniswap v4 hook that automatically protects stablecoin pools during depeg events.

The problem is simple: when stablecoins depeg — like USDC dropping to 88 cents in March 2023 — AMM liquidity providers take massive losses. Current pools have no built-in defense. Fees stay the same, large whales can drain the pool, and there's no cross-chain coordination.

Peg Guardian fixes this with three layers of on-chain protection."

---

### [0:30 – 1:00] How It Works (Architecture overview)

> **[Point to architecture diagram sections as you explain]**

"Layer one: **Dynamic Fees.** In `beforeSwap`, the hook reads the current price — either from Chainlink or from our Reactive Network oracle — calculates the peg deviation, and scales fees from zero to 100 basis points. The worse the depeg, the higher the fee. This discourages arbitrage that drains LPs.

Layer two: **Segmented Order Flow.** Large orders over $100K get an extra 20 bps surcharge. The hook normalizes token decimals, so whether you're swapping USDC with 6 decimals or DAI with 18, the threshold works correctly.

Layer three: **Cross-Chain Protection via Reactive Network.** When `afterSwap` detects deviation above 50 basis points, it emits a `RebalanceNeeded` event. Our `PegMonitorReactive` contract on the Reactive Network picks this up and triggers a callback on the destination chain, which updates the price AND executes a protective swap to buy back the depegged token."

---

### [1:00 – 1:45] Code Walkthrough (Screen share: VS Code)

> **[Switch to VS Code, show `StablecoinPegGuardianHook.sol`]**

"Let me show you the core logic. Here's `_beforeSwap` — first, we auto-fetch fresh Chainlink data with a try-catch so the oracle can never block swaps. Then we calculate deviation in basis points and compute the dynamic fee. For the segmented flow, `_normalizeSwapAmount` queries the token's `decimals()` and scales to 18 decimals before comparing against the $100K threshold."

> **[Scroll to `_afterSwap`]**

"In `afterSwap`, if deviation exceeds 50 bps, we emit `RebalanceNeeded` — that's the event the Reactive Network subscribes to."

> **[Switch to `PegGuardianCallback.sol`]**

"On the destination chain, `handleRebalance` updates the hook's price AND executes a protective swap through the pool, buying back the depegged stablecoin."

---

### [1:45 – 2:15] Tests (Terminal)

> **[Switch to terminal]**

"We have over 80 tests covering unit, fuzz, invariant, and gas benchmarks."

> **[Run `forge test`]**

"Unit tests verify deviation math, admin functions, and ownership transfer. Fuzz tests randomize prices to prove fee bounds hold. Invariant tests verify that the price is always positive and rebalance count never decreases. And the gas tests confirm we stay under 150K per swap."

> **[Wait for test output — all green]**

"All passing."

---

### [2:15 – 2:45] Live Frontend Demo (Browser)

> **[Switch to browser — frontend dashboard]**

"Here's the monitoring dashboard. At the top you can see the current peg status — price, deviation percentage, and the dynamic fee being applied right now.

Below that, the event feed shows recent `SwapExecuted` and `RebalanceNeeded` events live from the chain.

And in the admin panel, the contract owner can update price, set the Chainlink oracle, pause the hook in emergencies, or transfer ownership to a multisig Safe — all through the UI."

> **[If time allows, show the Etherscan transactions]**

"And you can verify everything on Sepolia Etherscan — here's the hook contract, the events, and the Reactive callback transactions."

---

### [2:45 – 3:00] Closing

> **[Back to architecture diagram or face cam]**

"To wrap up: Peg Guardian is a complete stablecoin protection system — dynamic fees, cross-chain reactive monitoring, and protective swaps — all built as a single Uniswap v4 hook. It's deployed on Sepolia with live Reactive Network integration on Lasna testnet, and it's ready for mainnet.

Thanks for watching!"

---

## Post-Recording Notes

- Upload to YouTube (unlisted or public) or Loom
- Copy the video link for the Hookathon submission form
- Make sure the video is accessible (not private/restricted)
- Double-check audio quality before submitting
