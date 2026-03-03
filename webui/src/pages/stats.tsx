import { BarChart3 } from "lucide-react";

export default function StatsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Statistics</h1>
        <p className="mt-1 text-sm text-slate-500">
          Token usage, latency, and error rate analytics
        </p>
      </div>
      <div className="glass rounded-2xl p-12 text-center">
        <BarChart3 className="mx-auto h-10 w-10 text-slate-400" />
        <p className="mt-3 text-sm text-slate-500">
          Statistics will populate as requests flow through the gateway
        </p>
      </div>
    </div>
  );
}
