const IS_TAURI = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

async function invokeIPC<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(cmd, args);
}

async function invokeHTTP<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const method = args ? "POST" : "GET";
  const resp = await fetch(`/api/v1/${cmd}`, {
    method,
    headers: { "Content-Type": "application/json" },
    body: args ? JSON.stringify(args) : undefined,
  });
  if (!resp.ok) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${resp.status}`);
  }
  const json = await resp.json();
  return json.data ?? json;
}

export const backend = IS_TAURI ? invokeIPC : invokeHTTP;
export { IS_TAURI };
