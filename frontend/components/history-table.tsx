import type { HistoryEvent } from "@/lib/strategyData";

function asDate(value: string): string {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone: "UTC",
  }).format(new Date(value));
}

function asUsd(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
}

type HistoryTableProps = {
  events: HistoryEvent[];
};

export function HistoryTable({ events }: HistoryTableProps) {
  return (
    <div className="overflow-hidden rounded-3xl border border-white/20 bg-white/80 backdrop-blur">
      <table className="w-full text-left text-sm">
        <thead className="bg-ink text-xs uppercase tracking-[0.15em] text-white/80">
          <tr>
            <th className="px-4 py-3">Time (UTC)</th>
            <th className="px-4 py-3">Pool</th>
            <th className="px-4 py-3">Event</th>
            <th className="px-4 py-3">Amount</th>
            <th className="px-4 py-3">Details</th>
          </tr>
        </thead>
        <tbody>
          {events.map((entry) => (
            <tr key={entry.id} className="border-t border-slate-200/80 align-top">
              <td className="px-4 py-3 font-mono text-xs text-steel">{asDate(entry.timestamp)}</td>
              <td className="px-4 py-3 text-ink">{entry.poolId}</td>
              <td className="px-4 py-3 font-medium text-ink">{entry.event}</td>
              <td className="px-4 py-3 text-ink">{entry.amountUsd > 0 ? asUsd(entry.amountUsd) : "-"}</td>
              <td className="px-4 py-3 text-steel">{entry.details}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
