# Commit Guide — Stablecoin Peg Guardian Hook

Run all commands from the project root:

```
cd /home/zarcc/Documents/GitHub/WEB3/uniswap/stablecoin-peg
```

---

Done

## Commit 1 — Initial project scaffold

```bash
git add .gitignore .github/
git commit -m "chore: initial project scaffold with .gitignore"
```

Done

## Commit 2 — Add PRD

```bash
git add prd.md
git commit -m "docs: add product requirements document (PRD)"
```

Done

## Commit 3 — Add README

```bash
git add README.md
git commit -m "docs: add project README"
```

Done

## Commit 4 — Add Foundry configuration

```bash
git add foundry.toml foundry.lock
git commit -m "chore: configure foundry (solc 0.8.26, evm cancun, optimizer)"
```

## Commit 5 — Install v4-core and v4-periphery

```bash
git add .gitmodules lib/v4-periphery lib/forge-std
git commit -m "chore: install uniswap v4-core, v4-periphery, and forge-std"
```

## Commit 6 — Add remappings

```bash
git add remappings.txt
git commit -m "chore: add solidity import remappings"
```

## Commit 7 — Add BaseHook contract

```bash
git add src/BaseHook.sol
git commit -m "feat: add BaseHook abstract contract from Uniswap library"
```

## Commit 8 — Add hook skeleton with permissions

```bash
git add src/StablecoinPegGuardianHook.sol
git commit -m "feat: add StablecoinPegGuardianHook skeleton with hook permissions

- beforeSwap, afterSwap, beforeAddLiquidity flags enabled
- Constructor with owner and PoolManager params
- getHookPermissions() override"
```

> [!TIP]
> At this point, reset the file to just the skeleton if you want a truly incremental history. Otherwise, committing the full file here is fine — the remaining commits will document the logical phases.

## Commit 9 — Add custom errors and events

```bash
git add -p src/StablecoinPegGuardianHook.sol
git commit -m "feat: add custom errors, events, and constants

- NotOwner, HookPaused, InvalidPrice, ZeroAddress errors
- SwapExecuted, RebalanceNeeded, LiquidityAdded events
- PriceUpdated, PegPriceUpdated, Paused/Unpaused events
- Fee constants: MAX_FEE, LARGECAP_SURCHARGE, thresholds"
```

> [!NOTE]
> If you committed the full file in Commit 8, use `git add -p` to stage only the relevant hunks for each commit, OR simply commit the full file once and use these messages as your commit message guide going forward.

## Commit 10 — Implement dynamic fee calculation

```bash
git commit --allow-empty -m "feat(hook): implement dynamic fee in _beforeSwap

- Linear fee scaling: 0-100 bps based on peg deviation
- Segmented order flow: +20 bps surcharge for orders >= \$100k
- OVERRIDE_FEE_FLAG for PoolManager fee override
- Fee capped at LPFeeLibrary.MAX_LP_FEE"
```

## Commit 11 — Implement rebalance detection

```bash
git commit --allow-empty -m "feat(hook): implement rebalance detection in _afterSwap

- Emits RebalanceNeeded when deviation >= 50 bps (0.5%)
- Increments rebalanceCount for monitoring
- Pause gate on _beforeAddLiquidity"
```

## Commit 12 — Add admin controls and ownership

```bash
git commit --allow-empty -m "feat(hook): add admin controls with 2-step ownership

- updatePrice() and setPegPrice() owner-only functions
- pause() / unpause() emergency circuit breaker
- transferOwnership() / acceptOwnership() 2-step pattern
- Wrapped modifier logic for gas optimization"
```

## Commit 13 — Add hook unit tests

```bash
git add test/StablecoinPegGuardianHook.t.sol
git commit -m "test: add comprehensive hook test suite (31 tests)

- Deviation calculation at 0%, 0.25%, 0.5%, 1%, 2%
- Admin function tests (price, peg, pause, ownership)
- Event emission verification
- Authorization revert tests"
```

## Commit 14 — Install reactive-lib

```bash
git add lib/reactive-lib
git commit -m "chore: install Reactive Network reactive-lib dependency"
```

## Commit 15 — Add Reactive interface constants

```bash
git add src/interfaces/IReactivePegGuardian.sol
git commit -m "feat(reactive): add shared event topic hash constants

- REBALANCE_NEEDED_TOPIC_0 precomputed via cast keccak
- PEG_PROTECTION_EXECUTED_TOPIC_0 precomputed"
```

## Commit 16 — Add PegMonitorReactive contract

```bash
git add src/reactive/PegMonitorReactive.sol
git commit -m "feat(reactive): add PegMonitorReactive contract

- Subscribes to RebalanceNeeded events on origin chain
- Decodes deviation and price data in react()
- Emits Callback to trigger PegGuardianCallback
- Follows Uniswap V2 Stop Order demo pattern"
```

## Commit 17 — Add PegGuardianCallback + callback integration

```bash
git add src/reactive/PegGuardianCallback.sol
git commit -m "feat(reactive): add PegGuardianCallback for destination chains

- Receives cross-chain callbacks from PegMonitorReactive
- Calls updatePriceFromCallback() on destination hook
- authorizedSenderOnly access control
- PegProtectionExecuted event emission"
```

## Commit 18 — Add callback integration to hook + tests

```bash
git add test/PegGuardianCallback.t.sol
git commit -m "feat(hook): add cross-chain callback support + integration tests

- authorizedCallback state and setAuthorizedCallback()
- updatePriceFromCallback() for authorized callbacks only
- 10 integration tests for callback flow
- All 41 tests pass, zero build warnings"
```

---

## Quick Reference — Simplified Version

If you prefer fewer interactive steps, here's a condensed approach that still gives clean history:

```bash
# 1-6: Project setup
git add .gitignore .github/ && git commit -m "chore: initial scaffold"
git add prd.md && git commit -m "docs: add PRD"
git add README.md && git commit -m "docs: add README"
git add foundry.toml foundry.lock && git commit -m "chore: foundry config"
git add .gitmodules lib/v4-periphery lib/forge-std && git commit -m "chore: install v4 deps"
git add remappings.txt && git commit -m "chore: add remappings"

# 7-8: Base contracts
git add src/BaseHook.sol && git commit -m "feat: add BaseHook contract"
git add src/StablecoinPegGuardianHook.sol && git commit -m "feat: add StablecoinPegGuardianHook with full Phase 2 logic"

# 9: Hook tests
git add test/StablecoinPegGuardianHook.t.sol && git commit -m "test: 31 hook tests (fees, admin, ownership)"

# 10-12: Reactive
git add lib/reactive-lib && git commit -m "chore: install reactive-lib"
git add src/interfaces/ && git commit -m "feat(reactive): add topic hash constants"
git add src/reactive/PegMonitorReactive.sol && git commit -m "feat(reactive): add PegMonitorReactive"
git add src/reactive/PegGuardianCallback.sol && git commit -m "feat(reactive): add PegGuardianCallback"

# 13: Callback tests
git add test/PegGuardianCallback.t.sol && git commit -m "test: 10 callback integration tests"

# 14: Final verification
git add -A && git commit -m "chore: final cleanup — 41/41 tests, zero warnings"
```

After all commits, verify:

```bash
forge build   # should show: Compiler run successful!
forge test    # should show: 41 tests passed, 0 failed
```
