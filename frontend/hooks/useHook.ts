"use client";

import {
  useReadContract,
  useReadContracts,
  useWatchContractEvent,
  usePublicClient,
} from "wagmi";
import { hookContract } from "@/lib/contracts";
import { formatUnits, type Log } from "viem";
import { useState, useCallback, useEffect } from "react";
import { STABLECOIN_PEG_GUARDIAN_HOOK_ABI } from "@/lib/abi/StablecoinPegGuardianHook";
import { HOOK_ADDRESS } from "@/lib/contracts";

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

// ── useRebalanceEvents: Fetch past + watch for new RebalanceNeeded ────

export function useRebalanceEvents(maxEvents = 20) {
  const [events, setEvents] = useState<RebalanceEvent[]>([]);
  const publicClient = usePublicClient();

  // Fetch historical events on mount
  useEffect(() => {
    if (!publicClient) return;

    async function fetchPastEvents() {
      try {
        const currentBlock = await publicClient!.getBlockNumber();
        const fromBlock = currentBlock > 900n ? currentBlock - 900n : 0n;
        const logs = await publicClient!.getContractEvents({
          address: HOOK_ADDRESS,
          abi: STABLECOIN_PEG_GUARDIAN_HOOK_ABI,
          eventName: "RebalanceNeeded",
          fromBlock,
          toBlock: "latest",
        });

        const pastEvents: RebalanceEvent[] = logs.map((log) => ({
          poolId: (log.args as { poolId?: string }).poolId ?? "",
          deviationBps:
            (log.args as { deviationBps?: bigint }).deviationBps ?? 0n,
          currentPrice: formatUnits(
            (log.args as { currentPrice?: bigint }).currentPrice ?? 0n,
            18,
          ),
          timestamp: Number(log.blockNumber) * 1000, // approximate
        }));

        setEvents((prev) =>
          [...pastEvents, ...prev]
            .filter(
              (e, i, arr) =>
                arr.findIndex(
                  (x) =>
                    x.poolId === e.poolId &&
                    x.deviationBps === e.deviationBps &&
                    x.timestamp === e.timestamp,
                ) === i,
            )
            .slice(0, maxEvents),
        );
      } catch (err) {
        console.error("Failed to fetch past RebalanceNeeded events:", err);
      }
    }

    fetchPastEvents();
  }, [publicClient, maxEvents]);

  // Watch for new real-time events
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

// ── useSwapEvents: Fetch past + watch for new SwapExecuted ────────────

export function useSwapEvents(maxEvents = 20) {
  const [events, setEvents] = useState<SwapEvent[]>([]);
  const publicClient = usePublicClient();

  // Fetch historical events on mount
  useEffect(() => {
    if (!publicClient) return;

    async function fetchPastEvents() {
      try {
        const currentBlock = await publicClient!.getBlockNumber();
        const fromBlock = currentBlock > 900n ? currentBlock - 900n : 0n;
        const logs = await publicClient!.getContractEvents({
          address: HOOK_ADDRESS,
          abi: STABLECOIN_PEG_GUARDIAN_HOOK_ABI,
          eventName: "SwapExecuted",
          fromBlock,
          toBlock: "latest",
        });
        console.log("SwapExecuted events:", logs);

        const pastEvents: SwapEvent[] = logs.map((log) => ({
          poolId: (log.args as { poolId?: string }).poolId ?? "",
          sender: (log.args as { sender?: string }).sender ?? "",
          fee: Number((log.args as { fee?: number }).fee ?? 0),
          deviationBps:
            (log.args as { deviationBps?: bigint }).deviationBps ?? 0n,
          timestamp: Number(log.blockNumber) * 1000,
        }));

        setEvents((prev) =>
          [...pastEvents, ...prev]
            .filter(
              (e, i, arr) =>
                arr.findIndex(
                  (x) =>
                    x.poolId === e.poolId &&
                    x.sender === e.sender &&
                    x.timestamp === e.timestamp,
                ) === i,
            )
            .slice(0, maxEvents),
        );
      } catch (err) {
        console.error("Failed to fetch past SwapExecuted events:", err);
      }
    }

    fetchPastEvents();
  }, [publicClient, maxEvents]);

  // Watch for new real-time events
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
