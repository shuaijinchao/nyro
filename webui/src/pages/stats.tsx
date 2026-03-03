import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis, PieChart, Pie, Cell } from "recharts";
import { backend } from "@/lib/backend";
import type { StatsOverview, StatsHourly, ModelStats, ProviderStats } from "@/lib/types";
import { Zap, Clock, Activity } from "lucide-react";

const COLORS = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#ec4899", "#06b6d4", "#84cc16"];

function fmt(n: number) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1) + "K";
  return String(n);
}

export default function StatsPage() {
  const [hours, setHours] = useState(24);

  const { data: overview } = useQuery<StatsOverview>({
    queryKey: ["stats-overview"],
    queryFn: () => backend("get_stats_overview"),
    refetchInterval: 10_000,
  });

  const { data: hourly = [] } = useQuery<StatsHourly[]>({
    queryKey: ["stats-hourly", hours],
    queryFn: () => backend("get_stats_hourly", { hours }),
    refetchInterval: 30_000,
  });

  const { data: modelStats = [] } = useQuery<ModelStats[]>({
    queryKey: ["stats-models"],
    queryFn: () => backend("get_stats_by_model"),
    refetchInterval: 30_000,
  });

  const { data: providerStats = [] } = useQuery<ProviderStats[]>({
    queryKey: ["stats-providers"],
    queryFn: () => backend("get_stats_by_provider"),
    refetchInterval: 30_000,
  });

  const tokenChart = hourly.map((h) => ({
    hour: h.hour.slice(11, 16),
    input: h.total_input_tokens,
    output: h.total_output_tokens,
  }));

  const modelPie = modelStats.slice(0, 8).map((m) => ({
    name: m.model,
    value: m.request_count,
  }));

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Statistics</h1>
          <p className="mt-1 text-sm text-slate-500">Token usage, latency, and error analytics</p>
        </div>
        <select
          value={hours}
          onChange={(e) => setHours(Number(e.target.value))}
          className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm outline-none"
        >
          <option value={6}>Last 6h</option>
          <option value={24}>Last 24h</option>
          <option value={72}>Last 3d</option>
          <option value={168}>Last 7d</option>
        </select>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {[
          { label: "Total Requests", value: fmt(overview?.total_requests ?? 0), icon: Activity, color: "text-blue-600" },
          { label: "Input Tokens", value: fmt(overview?.total_input_tokens ?? 0), icon: Zap, color: "text-amber-600" },
          { label: "Output Tokens", value: fmt(overview?.total_output_tokens ?? 0), icon: Zap, color: "text-green-600" },
          { label: "Avg Latency", value: `${(overview?.avg_duration_ms ?? 0).toFixed(0)}ms`, icon: Clock, color: "text-purple-600" },
        ].map((c) => (
          <div key={c.label} className="glass rounded-2xl p-5">
            <div className="flex items-center gap-2">
              <c.icon className={`h-4 w-4 ${c.color}`} />
              <p className="text-xs font-medium text-slate-500">{c.label}</p>
            </div>
            <p className="mt-2 text-2xl font-semibold text-slate-900">{c.value}</p>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <div className="glass rounded-2xl p-6">
          <h3 className="mb-4 text-sm font-semibold text-slate-800">Token Usage Over Time</h3>
          <div className="h-56">
            {tokenChart.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={tokenChart}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
                  <XAxis dataKey="hour" tick={{ fill: "#64748b", fontSize: 11 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: "#64748b", fontSize: 11 }} axisLine={false} tickLine={false} width={50} tickFormatter={fmt} />
                  <Tooltip />
                  <Bar dataKey="input" name="Input" stackId="a" fill="#3b82f6" />
                  <Bar dataKey="output" name="Output" stackId="a" fill="#10b981" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-slate-400">No data</div>
            )}
          </div>
        </div>

        <div className="glass rounded-2xl p-6">
          <h3 className="mb-4 text-sm font-semibold text-slate-800">Requests by Model</h3>
          <div className="h-56">
            {modelPie.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={modelPie}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={80}
                    paddingAngle={3}
                    dataKey="value"
                    label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                  >
                    {modelPie.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-slate-400">No data</div>
            )}
          </div>
        </div>
      </div>

      <div className="glass rounded-2xl p-6">
        <h3 className="mb-4 text-sm font-semibold text-slate-800">Provider Breakdown</h3>
        <div className="overflow-hidden rounded-xl border border-white/70 bg-white/50">
          <table className="w-full text-sm">
            <thead className="bg-white/70 text-slate-500">
              <tr>
                <th className="px-4 py-2.5 text-left font-medium">Provider</th>
                <th className="px-4 py-2.5 text-right font-medium">Requests</th>
                <th className="px-4 py-2.5 text-right font-medium">Errors</th>
                <th className="px-4 py-2.5 text-right font-medium">Error Rate</th>
                <th className="px-4 py-2.5 text-right font-medium">Avg Latency</th>
              </tr>
            </thead>
            <tbody>
              {providerStats.length === 0 && (
                <tr><td className="px-4 py-6 text-center text-slate-400" colSpan={5}>No data</td></tr>
              )}
              {providerStats.map((p) => (
                <tr key={p.provider} className="border-t border-white/70 text-slate-700">
                  <td className="px-4 py-2.5 font-medium">{p.provider}</td>
                  <td className="px-4 py-2.5 text-right">{fmt(p.request_count)}</td>
                  <td className="px-4 py-2.5 text-right text-red-500">{p.error_count}</td>
                  <td className="px-4 py-2.5 text-right">
                    {p.request_count > 0 ? ((p.error_count / p.request_count) * 100).toFixed(1) : "0"}%
                  </td>
                  <td className="px-4 py-2.5 text-right">{p.avg_duration_ms.toFixed(0)}ms</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
