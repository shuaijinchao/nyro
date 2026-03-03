import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { backend } from "@/lib/backend";
import type { Provider, CreateProvider, TestResult } from "@/lib/types";
import { Server, Plus, Trash2, CheckCircle, XCircle, Zap, Loader2 } from "lucide-react";

export default function ProvidersPage() {
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [testingId, setTestingId] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<Record<string, TestResult>>({});

  const { data: providers = [], isLoading } = useQuery<Provider[]>({
    queryKey: ["providers"],
    queryFn: () => backend("get_providers"),
  });

  const createMut = useMutation({
    mutationFn: (input: CreateProvider) =>
      backend("create_provider", { input }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["providers"] });
      setShowForm(false);
      resetForm();
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => backend("delete_provider", { id }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["providers"] }),
  });

  const [form, setForm] = useState<CreateProvider>({
    name: "",
    protocol: "openai",
    base_url: "https://api.openai.com",
    api_key: "",
  });

  function resetForm() {
    setForm({ name: "", protocol: "openai", base_url: "https://api.openai.com", api_key: "" });
  }

  async function handleTest(id: string) {
    setTestingId(id);
    try {
      const result = await backend<TestResult>("test_provider", { id });
      setTestResult((prev) => ({ ...prev, [id]: result }));
    } catch (e: unknown) {
      setTestResult((prev) => ({
        ...prev,
        [id]: { success: false, latency_ms: 0, error: String(e) },
      }));
    }
    setTestingId(null);
  }

  function protocolUrl(protocol: string) {
    switch (protocol) {
      case "anthropic": return "https://api.anthropic.com";
      case "gemini": return "https://generativelanguage.googleapis.com";
      default: return "https://api.openai.com";
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Providers</h1>
          <p className="mt-1 text-sm text-slate-500">
            Manage your LLM provider connections
          </p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-2.5 text-sm font-medium text-white shadow-md transition-all hover:bg-slate-800 cursor-pointer"
        >
          <Plus className="h-4 w-4" />
          Add Provider
        </button>
      </div>

      {showForm && (
        <div className="glass rounded-2xl p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">New Provider</h2>
          <div className="grid grid-cols-2 gap-4">
            <input
              placeholder="Name (e.g. OpenAI Production)"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            />
            <select
              value={form.protocol}
              onChange={(e) => setForm({ ...form, protocol: e.target.value, base_url: protocolUrl(e.target.value) })}
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            >
              <option value="openai">OpenAI</option>
              <option value="anthropic">Anthropic</option>
              <option value="gemini">Gemini</option>
            </select>
            <input
              placeholder="Base URL"
              value={form.base_url}
              onChange={(e) => setForm({ ...form, base_url: e.target.value })}
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            />
            <input
              placeholder="API Key"
              type="password"
              value={form.api_key}
              onChange={(e) => setForm({ ...form, api_key: e.target.value })}
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            />
          </div>
          <div className="flex gap-3">
            <button
              onClick={() => createMut.mutate(form)}
              disabled={createMut.isPending || !form.name || !form.api_key}
              className="rounded-xl bg-slate-900 px-5 py-2 text-sm font-medium text-white hover:bg-slate-800 cursor-pointer disabled:opacity-50"
            >
              {createMut.isPending ? "Creating..." : "Create"}
            </button>
            <button
              onClick={() => { setShowForm(false); resetForm(); }}
              className="rounded-xl border border-slate-200 px-5 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="text-center text-sm text-slate-500 py-12">Loading...</div>
      ) : providers.length === 0 ? (
        <div className="glass rounded-2xl p-12 text-center">
          <Server className="mx-auto h-10 w-10 text-slate-400" />
          <p className="mt-3 text-sm text-slate-500">No providers configured yet</p>
          <p className="mt-1 text-xs text-slate-400">Add a provider to get started</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {providers.map((p) => {
            const tr = testResult[p.id];
            return (
              <div key={p.id} className="glass rounded-2xl p-5">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-slate-100">
                      <Server className="h-5 w-5 text-slate-600" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-slate-900">{p.name}</span>
                        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-slate-500 uppercase">
                          {p.protocol}
                        </span>
                        {p.is_active ? (
                          <CheckCircle className="h-3.5 w-3.5 text-green-500" />
                        ) : (
                          <XCircle className="h-3.5 w-3.5 text-red-400" />
                        )}
                      </div>
                      <p className="mt-0.5 text-xs text-slate-500">{p.base_url}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleTest(p.id)}
                      disabled={testingId === p.id}
                      className="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium text-slate-600 border border-slate-200 hover:bg-slate-50 cursor-pointer disabled:opacity-50"
                    >
                      {testingId === p.id ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : (
                        <Zap className="h-3.5 w-3.5" />
                      )}
                      Test
                    </button>
                    <button
                      onClick={() => deleteMut.mutate(p.id)}
                      className="rounded-lg p-2 text-slate-400 transition-colors hover:bg-red-50 hover:text-red-500 cursor-pointer"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                </div>
                {tr && (
                  <div className={`mt-3 rounded-xl px-4 py-2.5 text-xs ${
                    tr.success ? "bg-green-50 text-green-700" : "bg-red-50 text-red-600"
                  }`}>
                    {tr.success
                      ? `Connected — ${tr.latency_ms}ms${tr.model ? ` (${tr.model})` : ""}`
                      : `Failed — ${tr.error}`
                    }
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
