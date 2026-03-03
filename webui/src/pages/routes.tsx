import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { backend } from "@/lib/backend";
import type { Route as RouteType, CreateRoute, Provider } from "@/lib/types";
import { Route as RouteIcon, Plus, Trash2 } from "lucide-react";

export default function RoutesPage() {
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);

  const { data: routes = [], isLoading } = useQuery<RouteType[]>({
    queryKey: ["routes"],
    queryFn: () => backend("list_routes"),
  });

  const { data: providers = [] } = useQuery<Provider[]>({
    queryKey: ["providers"],
    queryFn: () => backend("get_providers"),
  });

  const createMut = useMutation({
    mutationFn: (input: CreateRoute) => backend("create_route", { input }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["routes"] });
      setShowForm(false);
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => backend("delete_route", { id }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["routes"] }),
  });

  const [form, setForm] = useState<CreateRoute>({
    name: "",
    match_pattern: "*",
    target_provider: "",
    target_model: "",
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Routes</h1>
          <p className="mt-1 text-sm text-slate-500">
            Model-based routing rules
          </p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-2.5 text-sm font-medium text-white shadow-md transition-all hover:bg-slate-800 cursor-pointer"
        >
          <Plus className="h-4 w-4" />
          Add Route
        </button>
      </div>

      {showForm && (
        <div className="glass rounded-2xl p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">New Route</h2>
          <div className="grid grid-cols-2 gap-4">
            <input
              placeholder="Name"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            />
            <input
              placeholder="Match Pattern (e.g. gpt-4*, *)"
              value={form.match_pattern}
              onChange={(e) =>
                setForm({ ...form, match_pattern: e.target.value })
              }
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            />
            <select
              value={form.target_provider}
              onChange={(e) =>
                setForm({ ...form, target_provider: e.target.value })
              }
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            >
              <option value="">Select Provider</option>
              {providers.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
            <input
              placeholder="Target Model (e.g. gpt-4o)"
              value={form.target_model}
              onChange={(e) =>
                setForm({ ...form, target_model: e.target.value })
              }
              className="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm outline-none focus:border-slate-400"
            />
          </div>
          <div className="flex gap-3">
            <button
              onClick={() => createMut.mutate(form)}
              disabled={createMut.isPending}
              className="rounded-xl bg-slate-900 px-5 py-2 text-sm font-medium text-white hover:bg-slate-800 cursor-pointer disabled:opacity-50"
            >
              {createMut.isPending ? "Creating..." : "Create"}
            </button>
            <button
              onClick={() => setShowForm(false)}
              className="rounded-xl border border-slate-200 px-5 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="text-center text-sm text-slate-500 py-12">
          Loading...
        </div>
      ) : routes.length === 0 ? (
        <div className="glass rounded-2xl p-12 text-center">
          <RouteIcon className="mx-auto h-10 w-10 text-slate-400" />
          <p className="mt-3 text-sm text-slate-500">No routes configured</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {routes.map((r) => (
            <div
              key={r.id}
              className="glass flex items-center justify-between rounded-2xl p-5"
            >
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-slate-900">{r.name}</span>
                  <code className="rounded bg-slate-100 px-2 py-0.5 text-[11px] text-slate-600">
                    {r.match_pattern}
                  </code>
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  → {r.target_model}
                  {r.fallback_model && ` (fallback: ${r.fallback_model})`}
                </p>
              </div>
              <button
                onClick={() => deleteMut.mutate(r.id)}
                className="rounded-lg p-2 text-slate-400 transition-colors hover:bg-red-50 hover:text-red-500 cursor-pointer"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
