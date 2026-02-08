import type { StrategyPool } from "@/lib/strategyData";

function usd(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
}

type PoolCardProps = {
  pool: StrategyPool;
};

export function PoolCard({ pool }: PoolCardProps) {
  const insurancePoolUsd = pool.tvlUsd * (pool.insuranceCoveragePct / 100);
  const annualInsuranceFees = insurancePoolUsd * (pool.insuranceFeeAprPct / 100);

  return (
    <article className="group rounded-3xl border border-white/20 bg-white/80 p-6 shadow-glow backdrop-blur transition hover:-translate-y-1 hover:border-ember/40">
      <div className="mb-4 flex items-start justify-between gap-4">
        <div>
          <p className="mb-1 text-xs uppercase tracking-[0.2em] text-steel">{pool.strategyType}</p>
          <h3 className="text-2xl font-semibold text-ink">{pool.name}</h3>
        </div>
        <span className="rounded-full bg-ink px-3 py-1 text-xs font-medium text-white">ERC-4626</span>
      </div>

      <p className="mb-6 text-sm leading-relaxed text-steel">{pool.description}</p>

      <dl className="grid grid-cols-2 gap-3 text-sm text-ink">
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="text-xs uppercase tracking-wide text-steel">TVL</dt>
          <dd className="text-lg font-semibold">{usd(pool.tvlUsd)}</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="text-xs uppercase tracking-wide text-steel">Insurance Pool</dt>
          <dd className="text-lg font-semibold">{pool.insuranceCoveragePct}%</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="text-xs uppercase tracking-wide text-steel">Insurance Fee APR</dt>
          <dd className="text-lg font-semibold">{pool.insuranceFeeAprPct}%</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="text-xs uppercase tracking-wide text-steel">Annual Premium</dt>
          <dd className="text-lg font-semibold">{usd(annualInsuranceFees)}</dd>
        </div>
      </dl>

      <div className="mt-6 rounded-2xl bg-gradient-to-r from-ink to-steel p-4 text-white">
        <p className="text-xs uppercase tracking-widest text-white/70">Fee Economics</p>
        <p className="mt-2 text-sm">
          Management {pool.managementFeePct}% + Performance {pool.performanceFeePct}% with {pool.glueAllocationPct}% routed into
          Glue insurance rewards.
        </p>
        <p className="mt-2 text-sm text-mint">Insurer expected premium APR: {pool.insurerPremiumAprPct}%</p>
        <p className="mt-1 text-xs text-white/70">Coverage capital: {usd(insurancePoolUsd)}</p>
      </div>
    </article>
  );
}
