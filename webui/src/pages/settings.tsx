import { useQuery } from "@tanstack/react-query";
import { backend } from "@/lib/backend";
import type { GatewayStatus } from "@/lib/types";
import { Settings } from "lucide-react";

export default function SettingsPage() {
  const { data: status } = useQuery<GatewayStatus>({
    queryKey: ["gateway-status"],
    queryFn: () => backend("get_gateway_status"),
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Settings</h1>
        <p className="mt-1 text-sm text-slate-500">
          Gateway configuration
        </p>
      </div>

      <div className="glass rounded-2xl p-6 space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">
          Gateway Status
        </h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs text-slate-500">Status</p>
            <p className="mt-1 font-semibold text-green-600">
              {status?.status ?? "—"}
            </p>
          </div>
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs text-slate-500">Proxy Port</p>
            <p className="mt-1 font-semibold text-slate-900">
              {status?.proxy_port ?? "—"}
            </p>
          </div>
        </div>
      </div>

      <div className="glass rounded-2xl p-6 space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">Quick Start</h2>
        <div className="rounded-xl bg-slate-50 p-4">
          <p className="text-xs text-slate-500 mb-2">
            Use this base URL in your AI client SDK:
          </p>
          <code className="block rounded-lg bg-slate-900 px-4 py-3 text-sm text-green-400 font-mono select-all">
            http://127.0.0.1:{status?.proxy_port ?? 18080}/v1
          </code>
        </div>
      </div>

      <div className="glass rounded-2xl p-12 text-center">
        <Settings className="mx-auto h-10 w-10 text-slate-400" />
        <p className="mt-3 text-sm text-slate-500">
          More settings coming soon — proxy port, auth key, API key encryption,
          log retention, theme
        </p>
      </div>
    </div>
  );
}
