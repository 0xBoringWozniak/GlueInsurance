"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import Image from "next/image";
import { HistoryTable } from "@/components/history-table";
import { PoolCard } from "@/components/pool-card";
import { history, pools } from "@/lib/strategyData";

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
  const featureIcons = [
    { src: "/icon_shield.jpg", alt: "Coverage Shield" },
    { src: "/icon_idea.jpg", alt: "Risk Intelligence" },
    { src: "/icon_search.jpg", alt: "Transparent Analytics" },
    { src: "/icon_terminal.jpg", alt: "Onchain Infrastructure" },
  ];

  return (
    <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <header className="fade-in mb-6 rounded-2xl border border-white/30 bg-[var(--panel)] px-4 py-4 shadow-glow backdrop-blur md:px-6">
        <div className="flex flex-wrap items-center gap-4 md:flex-nowrap">
          <div className="flex items-center gap-3">
            <Image src="/logo.png" alt="Glue Insurance" width={128} height={52} className="h-auto w-32" priority />
            <span className="hidden text-sm font-medium text-steel sm:block">Glue Insurance</span>
          </div>
          <nav className="ml-0 flex items-center gap-2 md:ml-6">
            <button className="rounded-full border border-ink/10 bg-white px-4 py-2 text-sm font-semibold text-ink transition hover:bg-ink hover:text-white">
              Create Insurance
            </button>
            <button className="rounded-full border border-ink/10 bg-white px-4 py-2 text-sm font-semibold text-ink transition hover:bg-ink hover:text-white">
              Dashboard
            </button>
          </nav>
          <div className="ml-auto">
            <ConnectButton />
          </div>
        </div>
      </header>

      <section className="fade-in rounded-3xl border border-white/30 bg-[var(--panel)] p-6 shadow-glow backdrop-blur md:p-8">
        <div className="grid gap-6 lg:grid-cols-[1.6fr_1fr]">
          <div>
            <p className="text-xs uppercase tracking-[0.22em] text-steel">Glue Insurance</p>
            <h1 className="mt-2 text-3xl font-bold text-ink md:text-5xl">First Permissionless DeFi Strategy Insurance</h1>
            <p className="mt-3 max-w-2xl text-sm text-steel md:text-base">
              Management and performance fees are split between treasury and the Glue insurance pool. Insurers stake capital and
              receive premium flow as fees are accrued.
            </p>
            <div className="mt-5 flex flex-wrap gap-3">
              {featureIcons.map((icon) => (
                <div key={icon.src} className="rounded-2xl border border-white/40 bg-white/70 p-2">
                  <Image src={icon.src} alt={icon.alt} width={72} height={72} className="h-16 w-16 rounded-xl object-cover" />
                </div>
              ))}
            </div>
          </div>
          <div className="flex items-center justify-center">
            <Image
              src="/icon_world.jpg"
              alt="Global Coverage"
              width={320}
              height={320}
              className="h-auto w-full max-w-xs rounded-3xl border border-white/40 bg-white p-3"
            />
          </div>
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
          <h2 className="text-2xl font-semibold text-ink">Glue Pools</h2>
          <p className="text-xs uppercase tracking-widest text-steel">Pick your insurance</p>
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

      <footer className="mt-10 rounded-2xl border border-white/30 bg-[var(--panel)] p-5 text-sm text-steel backdrop-blur">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <p className="font-medium text-ink">Glue Insurance</p>
          <div className="flex flex-wrap items-center gap-4">
            <a href="https://x.com" target="_blank" rel="noreferrer" className="transition hover:text-ink">
              Twitter
            </a>
            <a href="https://discord.gg/ZxqcBxC96w" target="_blank" rel="noreferrer" className="transition hover:text-ink">
              Discord
            </a>
            <a href="https://defillama.com" target="_blank" rel="noreferrer" className="transition hover:text-ink">
              DefiLlama
            </a>
            <a href="https://glue.finance" target="_blank" rel="noreferrer" className="transition hover:text-ink">
              Website
            </a>
          </div>
        </div>
      </footer>
    </main>
  );
}
