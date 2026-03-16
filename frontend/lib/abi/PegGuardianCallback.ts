export const PEG_GUARDIAN_CALLBACK_ABI = [
  {
    type: "function",
    name: "HOOK_ADDRESS",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "handleRebalance",
    inputs: [
      { name: "", type: "address" },
      { name: "newPrice", type: "uint256" },
      { name: "deviationBps", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "PegProtectionExecuted",
    inputs: [
      { name: "hook", type: "address", indexed: true },
      { name: "newPrice", type: "uint256", indexed: false },
      { name: "deviationBps", type: "uint256", indexed: false },
    ],
  },
  { type: "error", name: "CallFailed", inputs: [] },
  { type: "error", name: "ZeroAddress", inputs: [] },
] as const;
