export type StrategyPool = {
  id: string;
  name: string;
  description: string;
  strategyType: "Basis" | "Delta Neutral" | "AI Optimized";
  tvlUsd: number;
  insuranceCoveragePct: number;
  insuranceFeeAprPct: number;
  managementFeePct: number;
  performanceFeePct: number;
  glueAllocationPct: number;
  insurerPremiumAprPct: number;
};

export type HistoryEvent = {
  id: string;
  poolId: string;
  timestamp: string;
  event: string;
  amountUsd: number;
  details: string;
};

export const pools: StrategyPool[] = [
  {
    id: "basis-usdc",
    name: "Basis Carry USDC",
    description: "Cash-and-carry futures basis strategy with dynamic hedge bands.",
    strategyType: "Basis",
    tvlUsd: 1_000_000,
    insuranceCoveragePct: 10,
    insuranceFeeAprPct: 1,
    managementFeePct: 2,
    performanceFeePct: 20,
    glueAllocationPct: 35,
    insurerPremiumAprPct: 3.8,
  },
  {
    id: "delta-neutral-eth",
    name: "Delta Neutral ETH",
    description: "Spot-perp delta neutral vault with volatility-aware rebalancing.",
    strategyType: "Delta Neutral",
    tvlUsd: 2_400_000,
    insuranceCoveragePct: 12,
    insuranceFeeAprPct: 1.2,
    managementFeePct: 2,
    performanceFeePct: 18,
    glueAllocationPct: 30,
    insurerPremiumAprPct: 4.2,
  },
  {
    id: "ai-yield-usdc",
    name: "AI Optimized Yield",
    description: "Machine-guided routing across lending and LP venues.",
    strategyType: "AI Optimized",
    tvlUsd: 3_100_000,
    insuranceCoveragePct: 8,
    insuranceFeeAprPct: 0.8,
    managementFeePct: 1.8,
    performanceFeePct: 15,
    glueAllocationPct: 40,
    insurerPremiumAprPct: 3.1,
  },
];

export const history: HistoryEvent[] = [
  {
    id: "evt-1",
    poolId: "basis-usdc",
    timestamp: "2026-02-07T10:45:00Z",
    event: "Management fee split",
    amountUsd: 5400,
    details: "35% routed to Glue insurance pool, 65% to treasury.",
  },
  {
    id: "evt-2",
    poolId: "delta-neutral-eth",
    timestamp: "2026-02-06T19:10:00Z",
    event: "Performance fee split",
    amountUsd: 18200,
    details: "Profit realization cycle, insurance premium reserves increased.",
  },
  {
    id: "evt-3",
    poolId: "ai-yield-usdc",
    timestamp: "2026-02-05T14:32:00Z",
    event: "Insurance premium paid",
    amountUsd: 4100,
    details: "Insurer rewards distributed pro-rata to staked underwriters.",
  },
  {
    id: "evt-4",
    poolId: "basis-usdc",
    timestamp: "2026-02-04T08:18:00Z",
    event: "Coverage ratio updated",
    amountUsd: 0,
    details: "Pool coverage moved from 9.5% to 10.0%.",
  },
];
