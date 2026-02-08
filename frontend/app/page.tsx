"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { HistoryTable } from "@/components/history-table";
import { PoolCard } from "@/components/pool-card";
import { history, pools } from "@/lib/mockData";

function aggregate() {
  const totalTvl = pools.reduce((sum, pool) => sum + pool.tvlUsd, 0);
  const totalInsurance = pools.reduce((sum, pool) => sum + (pool.tvlUsd * pool.insuranceCoveragePct) / 100, 0);
  const annualInsuranceFees = pools.reduce(
    (sum, pool) => sum + ((pool.tvlUsd * pool.insuranceCoveragePct) / 100) * (pool.insuranceFeeAprPct / 100),
    0
  );

  return { totalTvl, totalInsurance, annualInsuranceFees };
}

function usd(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
}

export default function HomePage() {
  const metrics = aggregate();

  return (
    <main className="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
      <section className="fade-in rounded-3xl border border-white/30 bg-[var(--panel)] p-6 shadow-glow backdrop-blur md:p-8">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div>
            <p className="text-xs uppercase tracking-[0.22em] text-steel">InsuranceGlue Protocol</p>
            <h1 className="mt-2 text-3xl font-bold text-ink md:text-5xl">ERC4626 Strategy Insurance Dashboard</h1>
            <p className="mt-3 max-w-2xl text-sm text-steel md:text-base">
              Management and performance fees are split between treasury and Glue insurance pool. Insurers stake capital and
              receive premium flow as fees are accrued.
            </p>
          </div>
          <ConnectButton />
        </div>

        <div className="mt-8 grid gap-4 md:grid-cols-3">
          <div className="rounded-2xl bg-white p-4">
            <p className="text-xs uppercase tracking-widest text-steel">Total TVL</p>
            <p className="mt-2 text-3xl font-semibold text-ink">{usd(metrics.totalTvl)}</p>
          </div>
          <div className="rounded-2xl bg-white p-4">
            <p className="text-xs uppercase tracking-widest text-steel">Insurance Capital</p>
            <p className="mt-2 text-3xl font-semibold text-ink">{usd(metrics.totalInsurance)}</p>
          </div>
          <div className="rounded-2xl bg-white p-4">
            <p className="text-xs uppercase tracking-widest text-steel">Annual Premium Flow</p>
            <p className="mt-2 text-3xl font-semibold text-ink">{usd(metrics.annualInsuranceFees)}</p>
          </div>
        </div>
      </section>

      <section className="mt-8">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-2xl font-semibold text-ink">Mock Strategy Pools</h2>
          <p className="text-xs uppercase tracking-widest text-steel">Basis / Delta Neutral / AI Optimized</p>
        </div>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {pools.map((pool) => (
            <PoolCard key={pool.id} pool={pool} />
          ))}
        </div>
      </section>

      <section className="mt-8 fade-in">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-2xl font-semibold text-ink">Premium & Fee History</h2>
          <p className="text-xs uppercase tracking-widest text-steel">Latest Events</p>
        </div>
        <HistoryTable events={history} />
      </section>
    </main>
  );
}
