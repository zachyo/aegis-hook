"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import {
  mainnet,
  sepolia,
  base,
  arbitrum,
  optimism,
  unichain,
  unichainSepolia,
} from "wagmi/chains";
import { ConnectKitProvider, getDefaultConfig } from "connectkit";

const config = createConfig(
  getDefaultConfig({
    chains: [sepolia],
    transports: {
      [mainnet.id]: http(),
      [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
      [base.id]: http(),
      [arbitrum.id]: http(),
      [optimism.id]: http(),
    },
    walletConnectProjectId:
      process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "",
    appName: "Stablecoin Peg Guardian",
  }),
);

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  console.log("RPC:", process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL);
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <ConnectKitProvider mode="light" theme="soft">
          {children}
        </ConnectKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
