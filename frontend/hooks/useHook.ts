"use client";

import {
  useReadContract,
  useReadContracts,
  useWatchContractEvent,
} from "wagmi";
import { hookContract } from "@/lib/contracts";
import { formatUnits } from "viem";
import { useState, useCallback } from "react";

// ── Types ─────────────────────────────────────────────────────────────

export interface HookState {
  currentPrice: string;
  pegPrice: string;
  deviationBps: bigint;
  rebalanceCount: bigint;
  paused: boolean;
  owner: string;
  isLoading: boolean;
  isError: boolean;
  refetch: () => void;
}

export interface RebalanceEvent {
  poolId: string;
  deviationBps: bigint;
  currentPrice: string;
  timestamp: number;
}

export interface SwapEvent {
  poolId: string;
  sender: string;
  fee: number;
  deviationBps: bigint;
  timestamp: number;
}

// ── useHookState: Read all core state variables ───────────────────────

export function useHookState(): HookState {
  const { data, isLoading, isError, refetch } = useReadContracts({
    contracts: [
      { ...hookContract, functionName: "currentPrice" },
      { ...hookContract, functionName: "pegPrice" },
      { ...hookContract, functionName: "getDeviationBps" },
      { ...hookContract, functionName: "rebalanceCount" },
      { ...hookContract, functionName: "paused" },
      { ...hookContract, functionName: "owner" },
    ],
  });

  console.log(data);

  const currentPrice = data?.[0]?.result as bigint | undefined;
  const pegPrice = data?.[1]?.result as bigint | undefined;
  const deviationBps = data?.[2]?.result as bigint | undefined;
  const rebalanceCount = data?.[3]?.result as bigint | undefined;
  const paused = data?.[4]?.result as boolean | undefined;
  const owner = data?.[5]?.result as string | undefined;

  return {
    currentPrice: currentPrice ? formatUnits(currentPrice, 18) : "—",
    pegPrice: pegPrice ? formatUnits(pegPrice, 18) : "—",
    deviationBps: deviationBps ?? 0n,
    rebalanceCount: rebalanceCount ?? 0n,
    paused: paused ?? false,
    owner: owner ?? "—",
    isLoading,
    isError,
    refetch,
  };
}

// ── useDeviationBps: Single read ──────────────────────────────────────

export function useDeviationBps() {
  return useReadContract({
    ...hookContract,
    functionName: "getDeviationBps",
  });
}

// ── useRebalanceCount: Single read ────────────────────────────────────

export function useRebalanceCount() {
  return useReadContract({
    ...hookContract,
    functionName: "rebalanceCount",
  });
}

// ── useRebalanceEvents: Watch for RebalanceNeeded events ──────────────

export function useRebalanceEvents(maxEvents = 20) {
  const [events, setEvents] = useState<RebalanceEvent[]>([]);

  useWatchContractEvent({
    ...hookContract,
    eventName: "RebalanceNeeded",
    onLogs: useCallback(
      (logs: unknown[]) => {
        const newEvents = (
          logs as Array<{
            args: {
              poolId: string;
              deviationBps: bigint;
              currentPrice: bigint;
            };
          }>
        ).map((log) => ({
          poolId: log.args.poolId,
          deviationBps: log.args.deviationBps,
          currentPrice: formatUnits(log.args.currentPrice, 18),
          timestamp: Date.now(),
        }));
        setEvents((prev) => [...newEvents, ...prev].slice(0, maxEvents));
      },
      [maxEvents],
    ),
  });

  return events;
}

// ── useSwapEvents: Watch for SwapExecuted events ──────────────────────

export function useSwapEvents(maxEvents = 20) {
  const [events, setEvents] = useState<SwapEvent[]>([]);

  useWatchContractEvent({
    ...hookContract,
    eventName: "SwapExecuted",
    onLogs: useCallback(
      (logs: unknown[]) => {
        const newEvents = (
          logs as Array<{
            args: {
              poolId: string;
              sender: string;
              fee: number;
              deviationBps: bigint;
            };
          }>
        ).map((log) => ({
          poolId: log.args.poolId,
          sender: log.args.sender,
          fee: log.args.fee,
          deviationBps: log.args.deviationBps,
          timestamp: Date.now(),
        }));
        setEvents((prev) => [...newEvents, ...prev].slice(0, maxEvents));
      },
      [maxEvents],
    ),
  });

  return events;
}
