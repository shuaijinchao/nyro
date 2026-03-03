import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { backend, IS_TAURI } from "@/lib/backend";
import type { GatewayStatus } from "@/lib/types";
import { Settings, Copy, Check } from "lucide-react";

export default function SettingsPage() {
  const [copied, setCopied] = useState(false);

  const { data: status } = useQuery<GatewayStatus>({
    queryKey: ["gateway-status"],
    queryFn: () => backend("get_gateway_status"),
  });

  const baseUrl = `http://127.0.0.1:${status?.proxy_port ?? 18080}/v1`;

  function copyUrl() {
    navigator.clipboard.writeText(baseUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Settings</h1>
        <p className="mt-1 text-sm text-slate-500">Gateway configuration and quick start guide</p>
      </div>

      <div className="glass rounded-2xl p-6 space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">Gateway Status</h2>
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs text-slate-500">Status</p>
            <p className="mt-1 font-semibold text-green-600">{status?.status ?? "–"}</p>
          </div>
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs text-slate-500">Proxy Port</p>
            <p className="mt-1 font-semibold text-slate-900">{status?.proxy_port ?? "–"}</p>
          </div>
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs text-slate-500">Mode</p>
            <p className="mt-1 font-semibold text-slate-900">{IS_TAURI ? "Desktop" : "Server"}</p>
          </div>
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs text-slate-500">Version</p>
            <p className="mt-1 font-semibold text-slate-900">0.1.0</p>
          </div>
        </div>
      </div>

      <div className="glass rounded-2xl p-6 space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">Quick Start</h2>
        <p className="text-sm text-slate-600">
          Point your AI client SDK to this base URL to start proxying requests:
        </p>
        <div className="flex items-center gap-2">
          <code className="flex-1 rounded-xl bg-slate-900 px-4 py-3 text-sm text-green-400 font-mono select-all">
            {baseUrl}
          </code>
          <button
            onClick={copyUrl}
            className="rounded-xl bg-slate-100 p-3 text-slate-600 hover:bg-slate-200 cursor-pointer transition-colors"
          >
            {copied ? <Check className="h-4 w-4 text-green-600" /> : <Copy className="h-4 w-4" />}
          </button>
        </div>
        <div className="space-y-3 mt-4">
          <p className="text-xs font-semibold text-slate-700 uppercase tracking-wider">Usage Examples</p>
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs font-medium text-slate-500 mb-2">Python (OpenAI SDK)</p>
            <pre className="text-xs text-slate-700 font-mono whitespace-pre-wrap">{`from openai import OpenAI

client = OpenAI(
    base_url="${baseUrl}",
    api_key="any-key",  # auth key if configured
)

resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello!"}],
)`}</pre>
          </div>
          <div className="rounded-xl bg-slate-50 p-4">
            <p className="text-xs font-medium text-slate-500 mb-2">curl</p>
            <pre className="text-xs text-slate-700 font-mono whitespace-pre-wrap">{`curl ${baseUrl}/chat/completions \\
  -H "Content-Type: application/json" \\
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}]}'`}</pre>
          </div>
        </div>
      </div>

      <div className="glass rounded-2xl p-6 space-y-4">
        <h2 className="text-lg font-semibold text-slate-900">Setup Guide</h2>
        <div className="space-y-3">
          {[
            { step: 1, title: "Add a Provider", desc: "Go to Providers → Add your OpenAI / Anthropic / Gemini API key" },
            { step: 2, title: "Create a Route", desc: "Go to Routes → Map model patterns (e.g. gpt-4*) to a provider" },
            { step: 3, title: "Use the Proxy", desc: "Point your SDK to the base URL above and start making requests" },
          ].map((s) => (
            <div key={s.step} className="flex gap-4 rounded-xl bg-slate-50 p-4">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-slate-900 text-sm font-bold text-white">
                {s.step}
              </div>
              <div>
                <p className="text-sm font-semibold text-slate-900">{s.title}</p>
                <p className="mt-0.5 text-xs text-slate-500">{s.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="glass rounded-2xl p-12 text-center">
        <Settings className="mx-auto h-10 w-10 text-slate-400" />
        <p className="mt-3 text-sm text-slate-500">
          Advanced settings (auth key, log retention, theme, proxy port) coming in next release
        </p>
      </div>
    </div>
  );
}
