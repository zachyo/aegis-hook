"use client";

import { useState } from "react";
import { useUpdatePrice, useSetPegPrice, usePauseHook, useUnpauseHook, useRefreshOracle } from "@/hooks/useHookAdmin";
import { useHookState } from "@/hooks/useHook";
import { Loader2, Settings, Pause, Play, RefreshCw } from "lucide-react";

interface AdminPanelProps {
  onSuccess?: () => void;
}

export function AdminPanel({ onSuccess }: AdminPanelProps) {
  const state = useHookState();
  const [priceInput, setPriceInput] = useState("");
  const [pegInput, setPegInput] = useState("");

  const { updatePrice, isPending: isUpdatingPrice, isConfirming: isConfirmingPrice, isSuccess: priceSuccess } = useUpdatePrice();
  const { setPegPrice, isPending: isSettingPeg, isConfirming: isConfirmingPeg, isSuccess: pegSuccess } = useSetPegPrice();
  const { pause, isPending: isPausing, isConfirming: isConfirmingPause } = usePauseHook();
  const { unpause, isPending: isUnpausing, isConfirming: isConfirmingUnpause } = useUnpauseHook();
  const { refreshOracle, isPending: isRefreshing, isConfirming: isConfirmingRefresh, isSuccess: refreshSuccess } = useRefreshOracle();

  const handleUpdatePrice = () => {
    if (!priceInput) return;
    updatePrice(priceInput);
    if (onSuccess) setTimeout(onSuccess, 2000);
  };

  const handleSetPeg = () => {
    if (!pegInput) return;
    setPegPrice(pegInput);
    if (onSuccess) setTimeout(onSuccess, 2000);
  };

  const handleTogglePause = () => {
    if (state.paused) {
      unpause();
    } else {
      pause();
    }
    if (onSuccess) setTimeout(onSuccess, 2000);
  };

  const handleRefreshOracle = () => {
    refreshOracle();
    if (onSuccess) setTimeout(onSuccess, 2000);
  };

  return (
    <div className="rounded-xl border border-border bg-background p-6">
      <div className="flex items-center gap-2 mb-6">
        <Settings className="w-5 h-5 text-muted-foreground" />
        <h3 className="text-xl font-medium tracking-tight">Admin Controls</h3>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
        {/* Update Price */}
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium text-muted-foreground">Update Oracle Price (USD)</label>
          <div className="flex gap-2">
            <input
              type="text"
              placeholder="1.0"
              value={priceInput}
              onChange={(e) => setPriceInput(e.target.value)}
              className="flex-1 px-4 py-2 rounded-lg border border-border bg-muted text-sm font-mono focus:outline-none focus:ring-2 focus:ring-zinc-400"
            />
            <button
              onClick={handleUpdatePrice}
              disabled={isUpdatingPrice || isConfirmingPrice || !priceInput}
              className="px-4 py-2 rounded-lg bg-zinc-900 text-zinc-50 dark:bg-zinc-100 dark:text-zinc-900 text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-40"
            >
              {isUpdatingPrice || isConfirmingPrice ? <Loader2 className="w-4 h-4 animate-spin" /> : "Set"}
            </button>
          </div>
          {priceSuccess && <span className="text-xs text-emerald-600 dark:text-emerald-400">Price updated ✓</span>}
        </div>

        {/* Set Peg Price */}
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium text-muted-foreground">Set Peg Price (USD)</label>
          <div className="flex gap-2">
            <input
              type="text"
              placeholder="1.0"
              value={pegInput}
              onChange={(e) => setPegInput(e.target.value)}
              className="flex-1 px-4 py-2 rounded-lg border border-border bg-muted text-sm font-mono focus:outline-none focus:ring-2 focus:ring-zinc-400"
            />
            <button
              onClick={handleSetPeg}
              disabled={isSettingPeg || isConfirmingPeg || !pegInput}
              className="px-4 py-2 rounded-lg bg-zinc-900 text-zinc-50 dark:bg-zinc-100 dark:text-zinc-900 text-sm font-medium hover:opacity-90 transition-opacity disabled:opacity-40"
            >
              {isSettingPeg || isConfirmingPeg ? <Loader2 className="w-4 h-4 animate-spin" /> : "Set"}
            </button>
          </div>
          {pegSuccess && <span className="text-xs text-emerald-600 dark:text-emerald-400">Peg updated ✓</span>}
        </div>

        {/* Pause / Unpause */}
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium text-muted-foreground">Hook State</label>
          <button
            onClick={handleTogglePause}
            disabled={isPausing || isUnpausing || isConfirmingPause || isConfirmingUnpause}
            className={`flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-opacity disabled:opacity-40 ${
              state.paused
                ? "bg-emerald-600 text-white hover:bg-emerald-700"
                : "bg-rose-600 text-white hover:bg-rose-700"
            }`}
          >
            {isPausing || isUnpausing || isConfirmingPause || isConfirmingUnpause ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : state.paused ? (
              <>
                <Play className="w-4 h-4" /> Unpause Hook
              </>
            ) : (
              <>
                <Pause className="w-4 h-4" /> Pause Hook
              </>
            )}
          </button>
        </div>

        {/* Refresh from Chainlink */}
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium text-muted-foreground">Chainlink Oracle</label>
          <button
            onClick={handleRefreshOracle}
            disabled={isRefreshing || isConfirmingRefresh}
            className="flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-border bg-background text-sm font-medium hover:bg-muted transition-colors disabled:opacity-40"
          >
            {isRefreshing || isConfirmingRefresh ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <>
                <RefreshCw className="w-4 h-4" /> Refresh Price from Oracle
              </>
            )}
          </button>
          {refreshSuccess && <span className="text-xs text-emerald-600 dark:text-emerald-400">Oracle refreshed ✓</span>}
        </div>
      </div>
    </div>
  );
}
