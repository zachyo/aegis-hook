"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { hookContract } from "@/lib/contracts";
import { parseUnits } from "viem";

// ── useUpdatePrice ────────────────────────────────────────────────────

export function useUpdatePrice() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  function updatePrice(priceString: string) {
    const priceWei = parseUnits(priceString, 18);
    writeContract({
      ...hookContract,
      functionName: "updatePrice",
      args: [priceWei],
    });
  }

  return { updatePrice, isPending, isConfirming, isSuccess, error };
}

// ── useSetPegPrice ────────────────────────────────────────────────────

export function useSetPegPrice() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  function setPegPrice(priceString: string) {
    const priceWei = parseUnits(priceString, 18);
    writeContract({
      ...hookContract,
      functionName: "setPegPrice",
      args: [priceWei],
    });
  }

  return { setPegPrice, isPending, isConfirming, isSuccess, error };
}

// ── usePauseHook ──────────────────────────────────────────────────────

export function usePauseHook() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  function pause() {
    writeContract({
      ...hookContract,
      functionName: "pause",
    });
  }

  return { pause, isPending, isConfirming, isSuccess, error };
}

// ── useUnpauseHook ────────────────────────────────────────────────────

export function useUnpauseHook() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  function unpause() {
    writeContract({
      ...hookContract,
      functionName: "unpause",
    });
  }

  return { unpause, isPending, isConfirming, isSuccess, error };
}

// ── useRefreshOracle ──────────────────────────────────────────────────

export function useRefreshOracle() {
  const { data: hash, writeContract, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  function refreshOracle() {
    writeContract({
      ...hookContract,
      functionName: "updatePriceFromOracle",
    });
  }

  return { refreshOracle, isPending, isConfirming, isSuccess, error };
}
