"use client";

import { WalletConnect } from "@/components/WalletConnect";
import { AdminPanel } from "@/components/AdminPanel";
import {
  useHookState,
  useRebalanceEvents,
  useSwapEvents,
} from "@/hooks/useHook";
import { useAccount } from "wagmi";
import {
  ShieldCheck,
  Activity,
  BarChart3,
  AlertCircle,
  RefreshCw,
  Loader2,
} from "lucide-react";

function formatBps(bps: bigint): string {
  return `${bps.toString()} bps`;
}

function shortenAddress(addr: string): string {
  if (addr.length < 10) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function getHealthLabel(bps: bigint): { label: string; className: string } {
  if (bps === 0n)
    return {
      label: "Healthy",
      className: "text-emerald-600 dark:text-emerald-400",
    };
  if (bps < 50n)
    return {
      label: "Nominal",
      className: "text-amber-600 dark:text-amber-400",
    };
  return { label: "Critical", className: "text-rose-600 dark:text-rose-400" };
}

function computeDynamicFee(deviationBps: bigint): string {
  const MAX_FEE = 10_000n;
  const MAX_DEVIATION = 100n;
  if (deviationBps >= MAX_DEVIATION) return MAX_FEE.toString();
  return ((deviationBps * MAX_FEE) / MAX_DEVIATION).toString();
}

export default function Home() {
  const { address } = useAccount();
  const state = useHookState();
  const rebalanceEvents = useRebalanceEvents();
  const swapEvents = useSwapEvents();

  const health = getHealthLabel(state.deviationBps);
  const dynamicFee = computeDynamicFee(state.deviationBps);
  const isOwner =
    address &&
    state.owner !== "—" &&
    address.toLowerCase() === state.owner.toLowerCase();
  console.log({ state });

  return (
    <div className="min-h-screen flex flex-col items-center p-8 sm:p-20 font-sans">
      {/* ── Header ────────────────────────────────────────────────────── */}
      <header className="w-full max-w-5xl flex justify-between items-center mb-16">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-zinc-900 dark:bg-zinc-100 rounded-md">
            <ShieldCheck className="w-6 h-6 text-zinc-50 dark:text-zinc-900" />
          </div>
          <h1 className="text-xl font-medium tracking-tight">Peg Guardian</h1>
        </div>
        <div className="flex items-center gap-4">
          {state.paused && (
            <span className="px-3 py-1 rounded-full text-xs font-semibold bg-rose-100 text-rose-700 dark:bg-rose-900/30 dark:text-rose-400">
              PAUSED
            </span>
          )}
          <button
            onClick={() => state.refetch()}
            className="p-2 rounded-lg border border-border hover:bg-muted transition-colors"
            title="Refresh data"
          >
            {state.isLoading ? (
              <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
            ) : (
              <RefreshCw className="w-4 h-4 text-muted-foreground" />
            )}
          </button>
          <WalletConnect />
        </div>
      </header>

      {/* ── Main ──────────────────────────────────────────────────────── */}
      <main className="w-full max-w-5xl flex flex-col gap-12">
        <section className="flex flex-col gap-4">
          <h2 className="text-3xl sm:text-4xl font-semibold tracking-tight">
            Stablecoin Protection Dashboard
          </h2>
          <p className="text-muted-foreground text-lg max-w-2xl">
            Monitor peg deviation, dynamic fees, and cross-chain reactive
            interventions for secured stablecoin pools.
          </p>
        </section>

        {/* ── Stats Grid ──────────────────────────────────────────────── */}
        <section className="grid grid-cols-1 sm:grid-cols-3 gap-6">
          {/* Current Peg */}
          <div className="p-6 rounded-xl border border-border bg-background shadow-sm flex flex-col gap-3">
            <div className="flex items-center gap-2 text-muted-foreground font-medium">
              <Activity className="w-4 h-4" />
              <span>Current Price</span>
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-4xl font-semibold tabular-nums">
                {state.isLoading ? "…" : state.currentPrice}
              </span>
              <span className="text-sm font-medium text-muted-foreground">
                USD
              </span>
            </div>
            <div className={`text-sm font-medium mt-2 ${health.className}`}>
              Deviation: {formatBps(state.deviationBps)} ({health.label})
            </div>
          </div>

          {/* Dynamic Fee */}
          <div className="p-6 rounded-xl border border-border bg-background shadow-sm flex flex-col gap-3">
            <div className="flex items-center gap-2 text-muted-foreground font-medium">
              <BarChart3 className="w-4 h-4" />
              <span>Dynamic Fee</span>
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-4xl font-semibold tabular-nums">
                {state.isLoading ? "…" : dynamicFee}
              </span>
              <span className="text-sm font-medium text-muted-foreground">
                hundredths bps
              </span>
            </div>
            <div className="text-sm font-medium text-zinc-500 mt-2">
              Peg: {state.pegPrice} USD
            </div>
          </div>

          {/* Rebalance Count */}
          <div className="p-6 rounded-xl border border-border bg-background shadow-sm flex flex-col gap-3">
            <div className="flex items-center gap-2 text-muted-foreground font-medium">
              <AlertCircle className="w-4 h-4" />
              <span>Protective Swaps</span>
            </div>
            <div className="flex items-baseline gap-2">
              <span className="text-4xl font-semibold tabular-nums">
                {state.isLoading ? "…" : state.rebalanceCount.toString()}
              </span>
            </div>
            <div className="text-sm font-medium text-zinc-500 mt-2">
              Reactive network interventions
            </div>
          </div>
        </section>

        {/* ── Recent Activity ─────────────────────────────────────────── */}
        <section className="flex flex-col gap-6 mt-8">
          <h3 className="text-2xl font-medium tracking-tight">
            Recent Activity
          </h3>
          <div className="rounded-xl border border-border bg-background overflow-hidden">
            <table className="w-full text-left text-sm">
              <thead className="bg-muted text-muted-foreground">
                <tr>
                  <th className="px-6 py-4 font-medium">Event</th>
                  <th className="px-6 py-4 font-medium">Deviation</th>
                  <th className="px-6 py-4 font-medium">Details</th>
                  <th className="px-6 py-4 font-medium text-right">Time</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rebalanceEvents.length === 0 && swapEvents.length === 0 && (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-6 py-8 text-center text-muted-foreground"
                    >
                      {state.isError
                        ? "Unable to connect. Ensure contracts are deployed and your wallet is connected."
                        : "Listening for events… Connect your wallet and ensure the hook is deployed."}
                    </td>
                  </tr>
                )}
                {rebalanceEvents.map((evt, i) => (
                  <tr key={`rebalance-${i}`}>
                    <td className="px-6 py-4 font-medium">Rebalance Needed</td>
                    <td className="px-6 py-4">{formatBps(evt.deviationBps)}</td>
                    <td className="px-6 py-4">Price: {evt.currentPrice}</td>
                    <td className="px-6 py-4 text-right text-muted-foreground">
                      {new Date(evt.timestamp).toLocaleTimeString()}
                    </td>
                  </tr>
                ))}
                {swapEvents.map((evt, i) => (
                  <tr key={`swap-${i}`}>
                    <td className="px-6 py-4 font-medium">Swap Executed</td>
                    <td className="px-6 py-4">{formatBps(evt.deviationBps)}</td>
                    <td className="px-6 py-4">
                      Fee: {evt.fee} · {shortenAddress(evt.sender)}
                    </td>
                    <td className="px-6 py-4 text-right text-muted-foreground">
                      {new Date(evt.timestamp).toLocaleTimeString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* ── Admin Panel (only visible to hook owner) ─────────────────── */}
        {isOwner && (
          <section className="mt-8">
            <AdminPanel onSuccess={() => state.refetch()} />
          </section>
        )}
      </main>
    </div>
  );
}
