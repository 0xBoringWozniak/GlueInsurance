# Interface Building Guide

## Default Stack

TypeScript + Next.js + RainbowKit + wagmi + viem + Tailwind CSS

## Project Setup

```bash
npx create-next-app@latest my-app --typescript --tailwind --app --src-dir
cd my-app
npm i @rainbow-me/rainbowkit wagmi viem @tanstack/react-query
```

## Wagmi Configuration

```typescript
// src/wagmi.config.ts
import { http, createConfig } from 'wagmi';
import { mainnet, base, optimism, sepolia, baseSepolia } from 'wagmi/chains';
import { getDefaultConfig } from '@rainbow-me/rainbowkit';

export const config = getDefaultConfig({
  appName: 'My Glue App',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_ID || 'YOUR_PROJECT_ID',
  chains: [mainnet, base, optimism, sepolia, baseSepolia],
  transports: {
    [mainnet.id]: http(),
    [base.id]: http(),
    [optimism.id]: http(),
    [sepolia.id]: http(),
    [baseSepolia.id]: http(),
  },
});
```

Get a WalletConnect Project ID at https://cloud.walletconnect.com (free).

## Layout with Providers

```tsx
// src/app/layout.tsx
'use client';

import { RainbowKitProvider } from '@rainbow-me/rainbowkit';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { config } from '@/wagmi.config';
import '@rainbow-me/rainbowkit/styles.css';
import './globals.css';

const queryClient = new QueryClient();

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <WagmiProvider config={config}>
          <QueryClientProvider client={queryClient}>
            <RainbowKitProvider>
              {children}
            </RainbowKitProvider>
          </QueryClientProvider>
        </WagmiProvider>
      </body>
    </html>
  );
}
```

## Contract ABI Integration

```typescript
// src/contracts/abi.ts
// After deploying, paste the ABI from artifacts/contracts/YourContract.sol/YourContract.json

export const CONTRACT_ADDRESS = '0xYourDeployedAddress' as const;

export const CONTRACT_ABI = [
  // Paste your contract ABI here
  // Or import from artifacts:
  // import artifact from '../../artifacts/contracts/YourContract.sol/YourContract.json';
  // export const CONTRACT_ABI = artifact.abi;
] as const;
```

## Core Component Template

```tsx
// src/components/InteractPanel.tsx
'use client';

import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatEther } from 'viem';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { CONTRACT_ADDRESS, CONTRACT_ABI } from '@/contracts/abi';

export function InteractPanel() {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState('');

  // Read contract data
  const { data: totalSupply } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'totalSupply',
  });

  const { data: userBalance } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // Write contract
  const { writeContract, data: txHash, isPending } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const handleUnglue = () => {
    if (!amount || !address) return;
    writeContract({
      address: CONTRACT_ADDRESS,
      abi: CONTRACT_ABI,
      functionName: 'unglue',
      args: [
        ['0x0000000000000000000000000000000000000000'], // ETH collateral
        parseEther(amount),
        [],       // empty tokenIds for ERC20
        address,  // recipient = self
      ],
    });
  };

  return (
    <div className="max-w-md mx-auto p-6 space-y-4">
      <ConnectButton />

      {isConnected && (
        <>
          <div className="text-sm text-gray-600">
            <p>Total Supply: {totalSupply ? formatEther(totalSupply as bigint) : '...'}</p>
            <p>Your Balance: {userBalance ? formatEther(userBalance as bigint) : '...'}</p>
          </div>

          <input
            type="text"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="Amount to unglue"
            className="w-full p-2 border rounded"
          />

          <button
            onClick={handleUnglue}
            disabled={isPending || isConfirming}
            className="w-full p-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {isPending ? 'Confirming...' : isConfirming ? 'Processing...' : 'Unglue'}
          </button>

          {isSuccess && (
            <p className="text-green-600">Transaction confirmed! ✅</p>
          )}
        </>
      )}
    </div>
  );
}
```

## Sending ETH to Glue (Deposit Collateral)

```tsx
import { useSendTransaction } from 'wagmi';
import { parseEther } from 'viem';

function DepositCollateral({ glueAddress }: { glueAddress: `0x${string}` }) {
  const [amount, setAmount] = useState('');
  const { sendTransaction, isPending } = useSendTransaction();

  const handleDeposit = () => {
    sendTransaction({
      to: glueAddress,
      value: parseEther(amount),
    });
  };

  return (
    <div>
      <input value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="ETH amount" />
      <button onClick={handleDeposit} disabled={isPending}>
        {isPending ? 'Sending...' : 'Send ETH to Glue'}
      </button>
    </div>
  );
}
```

## Reading Glue Data

```tsx
// Read collateral balance in a Glue
const { data: ethBacking } = useReadContract({
  address: GLUE_ADDRESS,
  abi: GLUE_ERC20_ABI,
  functionName: 'getBalance',
  args: ['0x0000000000000000000000000000000000000000'], // ETH
});

// Check if token is sticky
const { data: stickyInfo } = useReadContract({
  address: GLUE_STICK_ERC20_ADDRESS,
  abi: GLUE_STICK_ABI,
  functionName: 'isStickyToken',
  args: [tokenAddress],
});
```

## Error Handling Pattern

```tsx
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';

function WriteWithErrors() {
  const { writeContract, data: txHash, error: writeError, isPending } = useWriteContract();

  const { 
    isLoading: isConfirming, 
    isSuccess, 
    error: confirmError 
  } = useWaitForTransactionReceipt({ hash: txHash });

  return (
    <div>
      <button onClick={() => writeContract({...})} disabled={isPending || isConfirming}>
        {isPending ? 'Sign in wallet...' : isConfirming ? 'Confirming...' : 'Submit'}
      </button>
      
      {writeError && (
        <p className="text-red-600">
          Error: {writeError.message.includes('user rejected') 
            ? 'Transaction rejected' 
            : writeError.message}
        </p>
      )}
      
      {confirmError && (
        <p className="text-red-600">Transaction failed: {confirmError.message}</p>
      )}
      
      {isSuccess && <p className="text-green-600">Success! ✅</p>}
    </div>
  );
}
```

## Environment Variables

```bash
# .env.local
NEXT_PUBLIC_WALLETCONNECT_ID=your_walletconnect_project_id
NEXT_PUBLIC_CONTRACT_ADDRESS=0xYourDeployedAddress
NEXT_PUBLIC_ALCHEMY_KEY=your_alchemy_key_optional
```

## Interface Deployment: Vercel

### Step-by-Step

```bash
# 1. Install Vercel CLI
npm i -g vercel

# 2. Login
vercel login

# 3. Build locally first (check for errors)
npm run build

# 4. Test locally
npm run dev

# 5. Deploy
vercel

# 6. Follow prompts:
#    - Link to existing project? → No
#    - Project name? → my-glue-app
#    - Root directory? → ./ (default)
#    - Build command? → next build (default)
#    - Output directory? → .next (default)

# 7. Set environment variables
# Go to: vercel.com → Your Project → Settings → Environment Variables
# Add: NEXT_PUBLIC_WALLETCONNECT_ID, NEXT_PUBLIC_CONTRACT_ADDRESS, etc.

# 8. Redeploy with env vars
vercel --prod
```

### Custom Domain

1. Go to Vercel Dashboard → Your Project → Settings → Domains
2. Add your domain (e.g., `app.mytoken.xyz`)
3. Update DNS records as instructed
4. SSL certificate auto-generated

## Interface Deployment: Supabase (If Backend Needed)

For analytics, user profiles, leaderboards, or any backend data:

```bash
# 1. Create Supabase project at supabase.com
# 2. Get URL + anon key from Settings → API

# 3. Install Supabase client
npm i @supabase/supabase-js

# 4. Create client
```

```typescript
// src/lib/supabase.ts
import { createClient } from '@supabase/supabase-js';

export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);
```

```bash
# 5. Add env vars to Vercel:
#    NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
#    NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key

# 6. Redeploy
vercel --prod
```

## Responsive UI Tips

```tsx
// Mobile-first, works on all screens
<div className="min-h-screen bg-gray-50">
  <header className="p-4 flex justify-between items-center">
    <h1 className="text-xl font-bold">My Glue App</h1>
    <ConnectButton />
  </header>
  
  <main className="max-w-lg mx-auto p-4 space-y-4">
    {/* Your components */}
  </main>
</div>
```

## Checklist Before Launch

1. ✅ All contract functions have proper error handling in UI
2. ✅ Loading states shown during transactions
3. ✅ Success/error messages displayed
4. ✅ Works on mobile (responsive)
5. ✅ WalletConnect ID set (not placeholder)
6. ✅ Contract addresses updated to deployed addresses
7. ✅ Environment variables set in Vercel
8. ✅ Tested on testnet with real wallet
9. ✅ Network switching works (if multi-chain)
10. ✅ Custom domain configured (optional)
