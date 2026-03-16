import { STABLECOIN_PEG_GUARDIAN_HOOK_ABI } from "./abi/StablecoinPegGuardianHook";
import { PEG_GUARDIAN_CALLBACK_ABI } from "./abi/PegGuardianCallback";

// ── Contract Addresses ────────────────────────────────────────────────
// Replace these with your deployed contract addresses after running
// `forge script script/Deploy.s.sol` on a testnet or mainnet.

export const HOOK_ADDRESS =
  (process.env.NEXT_PUBLIC_HOOK_ADDRESS as `0x${string}`) ??
  "0x0000000000000000000000000000000000000000";

export const CALLBACK_ADDRESS =
  (process.env.NEXT_PUBLIC_CALLBACK_ADDRESS as `0x${string}`) ??
  "0x0000000000000000000000000000000000000000";

// ── Contract Configs (for wagmi useReadContract / useWriteContract) ───
export const hookContract = {
  address: HOOK_ADDRESS,
  abi: STABLECOIN_PEG_GUARDIAN_HOOK_ABI,
} as const;

export const callbackContract = {
  address: CALLBACK_ADDRESS,
  abi: PEG_GUARDIAN_CALLBACK_ABI,
} as const;
