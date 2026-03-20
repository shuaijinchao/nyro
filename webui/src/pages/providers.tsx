import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useEffect, useMemo, useRef, useState } from "react";
import { backend } from "@/lib/backend";
import { localizeBackendErrorMessage } from "@/lib/backend-error";
import type {
  Provider,
  CreateProvider,
  UpdateProvider,
  TestResult,
  ProviderPreset,
  ProviderChannelPreset,
  ProviderProtocol,
} from "@/lib/types";
import {
  Server,
  Plus,
  Trash2,
  CheckCircle,
  XCircle,
  Zap,
  Loader2,
  Pencil,
  X,
  ChevronLeft,
  ChevronRight,
  Eye,
  EyeOff,
  Info,
} from "lucide-react";
import { useLocale } from "@/lib/i18n";
import { ProviderIcon } from "@/components/ui/provider-icon";
import { NyroIcon } from "@/components/ui/nyro-icon";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

function protocolUrl(protocol: string) {
  switch (protocol) {
    case "anthropic": return "https://api.anthropic.com";
    case "gemini": return "https://generativelanguage.googleapis.com";
    default: return "https://api.openai.com";
  }
}

const emptyCreate: CreateProvider = {
  name: "",
  vendor: undefined,
  protocol: "openai",
  base_url: "https://api.openai.com",
  preset_key: "",
  channel: "",
  models_endpoint: "",
  models_source: "",
  capabilities_source: "",
  static_models: "",
  api_key: "",
};
const PAGE_SIZE = 6;
const DEFAULT_PRESET_ID = "custom";
const protocolOptions = [
  { label: "OpenAI", value: "openai" },
  { label: "Anthropic", value: "anthropic" },
  { label: "Gemini", value: "gemini" },
] as const satisfies ReadonlyArray<{ label: string; value: ProviderProtocol }>;

function availableProtocolsForPreset(
  preset?: ProviderPreset | null,
  channelId?: string,
): ProviderProtocol[] {
  if (!preset || preset.id === DEFAULT_PRESET_ID) {
    return protocolOptions.map((item) => item.value);
  }

  const byChannel = preset.channels?.find((channel) => channel.id === channelId);
  const collectKeys = (channels: ProviderChannelPreset[]) =>
    channels.flatMap((channel) => Object.keys(channel.baseUrls ?? {}));

  const protocolKeys = byChannel
    ? Object.keys(byChannel.baseUrls ?? {})
    : collectKeys(preset.channels ?? []);

  const known = new Set(protocolOptions.map((item) => item.value));
  const filtered = protocolKeys.filter((key): key is ProviderProtocol =>
    known.has(key as ProviderProtocol),
  );

  return filtered.length ? filtered : protocolOptions.map((item) => item.value);
}

function resolvePresetProtocol(
  preset: ProviderPreset,
  channelId?: string,
  preferred?: ProviderProtocol,
): ProviderProtocol {
  const available = availableProtocolsForPreset(preset, channelId);
  if (preferred && available.includes(preferred)) return preferred;
  if (available.includes(preset.defaultProtocol)) return preset.defaultProtocol;
  return available[0] ?? preset.defaultProtocol;
}

function presetLabel(preset: ProviderPreset, isZh: boolean) {
  return isZh ? preset.label.zh : preset.label.en;
}

function presetLabelClass(preset: ProviderPreset, isZh: boolean) {
  const len = presetLabel(preset, isZh).trim().length;
  if (len >= 16) return "provider-preset-label provider-preset-label-micro";
  if (len >= 12) return "provider-preset-label provider-preset-label-compact";
  return "provider-preset-label";
}

function channelLabel(channel: ProviderChannelPreset, isZh: boolean) {
  return isZh ? channel.label.zh : channel.label.en;
}

function toGatewayBaseUrl(url: string) {
  const normalized = url.trim().replace(/\/+$/, "");
  return normalized;
}

function defaultModelsEndpoint(baseUrl: string, protocol: ProviderProtocol) {
  const normalized = baseUrl.trim().replace(/\/+$/, "");
  let parsed: URL | null = null;
  try {
    parsed = new URL(normalized);
  } catch {
    parsed = null;
  }

  if (protocol === "openai" || protocol === "anthropic") {
    // OpenRouter model discovery endpoint should be /api/v1/models.
    if (parsed?.host === "openrouter.ai") {
      const pathname = parsed.pathname.replace(/\/+$/, "");
      if (pathname === "/api" || pathname === "/api/v1") {
        return `${parsed.origin}/api/v1/models`;
      }
    }

    try {
      const pathname = new URL(normalized).pathname.replace(/\/+$/, "");
      return pathname && pathname !== "/" ? `${normalized}/models` : `${normalized}/v1/models`;
    } catch {
      return normalized.endsWith("/v1") ? `${normalized}/models` : `${normalized}/v1/models`;
    }
  }

  if (protocol === "gemini") {
    return `${normalized}/v1beta/models`;
  }

  return "";
}

function joinStaticModels(models?: string[]) {
  return models?.join("\n") ?? "";
}

function fallbackChannelPreset(): ProviderChannelPreset {
  return {
    id: "default",
    label: { zh: "默认", en: "Default" },
    baseUrls: {},
  };
}

function fallbackProviderPreset(): ProviderPreset {
  return {
    id: DEFAULT_PRESET_ID,
    label: { zh: "自定义", en: "Custom" },
    defaultProtocol: "openai",
    channels: [],
  };
}

function presetChannels(preset?: ProviderPreset | null) {
  return preset?.channels?.length ? preset.channels : [fallbackChannelPreset()];
}

function resolvePresetConfig(
  preset: ProviderPreset,
  protocol: ProviderProtocol,
  channelId?: string,
) {
  const channel = presetChannels(preset).find((item) => item.id === channelId) ?? presetChannels(preset)[0];
  const sourceBaseUrls = channel?.baseUrls ?? {};
  const rawBaseUrl = sourceBaseUrls[protocol];
  const baseUrl = rawBaseUrl ? toGatewayBaseUrl(rawBaseUrl) : "";
  const modelsSource = channel?.modelsSource ?? channel?.modelsEndpoint ?? "";
  const capabilitiesSource = channel?.capabilitiesSource ?? "";
  const apiKey = channel?.apiKey ?? "";
  const staticModels = joinStaticModels(channel?.staticModels);

  return {
    baseUrl,
    modelsSource,
    capabilitiesSource,
    apiKey,
    staticModels,
    channel,
  };
}

function FieldLabel({ children, info }: { children: string; info?: string }) {
  return (
    <label className="ml-1 inline-flex items-center gap-1 text-xs leading-none font-normal text-slate-900">
      <span>{children}</span>
      {info ? (
        <TooltipProvider delayDuration={120}>
          <Tooltip>
            <TooltipTrigger asChild>
              <span
                className="inline-flex cursor-help text-slate-400 hover:text-slate-600"
                aria-label={info}
              >
                <Info className="h-3.5 w-3.5" />
              </span>
            </TooltipTrigger>
            <TooltipContent>{info}</TooltipContent>
          </Tooltip>
        </TooltipProvider>
      ) : null}
    </label>
  );
}

type TestLogLevel = "info" | "success" | "error";

type TestLogEntry = {
  timestamp: string;
  level: TestLogLevel;
  message: string;
};

const PROVIDER_TEST_RESULTS_STORAGE_KEY = "nyro.provider-test-results.v1";

function nowTimestamp() {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  const ss = String(now.getSeconds()).padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
}

function loadProviderTestResults(): Record<string, TestResult> {
  if (typeof window === "undefined") return {};
  try {
    const raw = window.localStorage.getItem(PROVIDER_TEST_RESULTS_STORAGE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as Record<string, TestResult>;
    if (!parsed || typeof parsed !== "object") return {};

    const normalized: Record<string, TestResult> = {};
    for (const [id, value] of Object.entries(parsed)) {
      if (!value || typeof value !== "object" || typeof value.success !== "boolean") continue;
      normalized[id] = {
        success: value.success,
        latency_ms: Number.isFinite(value.latency_ms) ? value.latency_ms : 0,
        model: typeof value.model === "string" ? value.model : undefined,
        error: typeof value.error === "string" ? value.error : undefined,
      };
    }
    return normalized;
  } catch {
    return {};
  }
}

function saveProviderTestResults(results: Record<string, TestResult>) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PROVIDER_TEST_RESULTS_STORAGE_KEY, JSON.stringify(results));
  } catch {
    // Ignore storage errors to avoid breaking provider UI.
  }
}

export default function ProvidersPage() {
  const { locale } = useLocale();
  const isZh = locale === "zh-CN";

  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [testingId, setTestingId] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<Record<string, TestResult>>(loadProviderTestResults);
  const [testDialogOpen, setTestDialogOpen] = useState(false);
  const [testLogs, setTestLogs] = useState<TestLogEntry[]>([]);
  const [isTestRunning, setIsTestRunning] = useState(false);
  const [testTarget, setTestTarget] = useState<Provider | null>(null);
  const [providerToDelete, setProviderToDelete] = useState<Provider | null>(null);
  const [selectedPresetId, setSelectedPresetId] = useState(DEFAULT_PRESET_ID);
  const [showCreateApiKey, setShowCreateApiKey] = useState(true);
  const [showEditApiKey, setShowEditApiKey] = useState(false);
  const [errorDialog, setErrorDialog] = useState<{ title: string; description?: string } | null>(null);
  const activeTestRunRef = useRef(0);
  const logsContainerRef = useRef<HTMLDivElement | null>(null);

  const { data: providers = [], isLoading } = useQuery<Provider[]>({
    queryKey: ["providers"],
    queryFn: () => backend("get_providers"),
  });
  const { data: providerPresetsRaw = [] } = useQuery<ProviderPreset[]>({
    queryKey: ["provider-presets"],
    queryFn: () => backend("get_provider_presets"),
  });
  const providerPresets = useMemo(
    () => (providerPresetsRaw.length ? providerPresetsRaw : [fallbackProviderPreset()]),
    [providerPresetsRaw],
  );

  const [form, setForm] = useState<CreateProvider>(emptyCreate);
  const selectedPreset = useMemo(
    () => providerPresets.find((preset) => preset.id === selectedPresetId) ?? null,
    [providerPresets, selectedPresetId],
  );
  useEffect(() => {
    if (providerPresets.some((preset) => preset.id === selectedPresetId)) return;
    setSelectedPresetId(providerPresets[0]?.id ?? DEFAULT_PRESET_ID);
  }, [providerPresets, selectedPresetId]);

  const [editForm, setEditForm] = useState<UpdateProvider & { id: string }>({
    id: "",
    name: "",
    vendor: undefined,
    protocol: "",
    base_url: "",
    preset_key: "",
    channel: "",
    models_endpoint: "",
    models_source: "",
    capabilities_source: "",
    static_models: "",
    api_key: "",
  });

  const createMut = useMutation({
    mutationFn: (input: CreateProvider) => backend<Provider>("create_provider", { input }),
    onSuccess: async (createdProvider: Provider) => {
      qc.invalidateQueries({ queryKey: ["providers"] });
      setShowForm(false);
      setSelectedPresetId(DEFAULT_PRESET_ID);
      setForm(emptyCreate);
      await handleTest(createdProvider);
    },
    onError: (error: unknown) => {
      showErrorDialog("创建提供商失败", "Failed to create provider", error);
    },
  });

  const [editError, setEditError] = useState<string | null>(null);

  const updateMut = useMutation({
    mutationFn: ({ id, ...input }: UpdateProvider & { id: string }) =>
      backend("update_provider", { id, input }),
    onSuccess: () => {
      setEditError(null);
      qc.invalidateQueries({ queryKey: ["providers"] });
      setEditingId(null);
    },
    onError: (err: Error) => {
      setEditError(String(err));
      showErrorDialog("保存提供商失败", "Failed to save provider", err);
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => backend("delete_provider", { id }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["providers"] }),
    onError: (error: unknown) => {
      showErrorDialog("删除提供商失败", "Failed to delete provider", error);
    },
  });

  function appendTestLog(level: TestLogLevel, message: string) {
    setTestLogs((prev) => [...prev, { timestamp: nowTimestamp(), level, message }]);
  }

  function normalizeErrorMessage(error: unknown) {
    return localizeBackendErrorMessage(error, isZh);
  }

  function showErrorDialog(titleZh: string, titleEn: string, error: unknown) {
    setErrorDialog({
      title: isZh ? titleZh : titleEn,
      description: normalizeErrorMessage(error),
    });
  }

  function closeTestDialog() {
    activeTestRunRef.current += 1;
    setIsTestRunning(false);
    setTestingId(null);
    setTestDialogOpen(false);
  }

  async function handleTest(provider: Provider) {
    const runId = activeTestRunRef.current + 1;
    activeTestRunRef.current = runId;
    const isCanceled = () => activeTestRunRef.current !== runId;

    setTestingId(provider.id);
    setTestTarget(provider);
    setTestLogs([]);
    setTestDialogOpen(true);
    setIsTestRunning(true);
    setTestResult((prev) => {
      const next = { ...prev };
      delete next[provider.id];
      return next;
    });

    const finish = (result: TestResult, finalMessage: string, level: "success" | "error") => {
      if (isCanceled()) return;
      appendTestLog(level, finalMessage);
      setTestResult((prev) => ({ ...prev, [provider.id]: result }));
      setIsTestRunning(false);
      setTestingId(null);
    };

    try {
      if (!provider.base_url) {
        finish(
          { success: false, latency_ms: 0, model: undefined, error: "Base URL is empty" },
          isZh ? "✗ Base URL 为空，无法开始测试" : "✗ Base URL is empty, unable to start test",
          "error",
        );
        return;
      }

      try {
        new URL(provider.base_url);
      } catch {
        finish(
          { success: false, latency_ms: 0, model: undefined, error: "Invalid Base URL format" },
          isZh ? "✗ Base URL 格式不合法" : "✗ Base URL format is invalid",
          "error",
        );
        return;
      }

      appendTestLog("info", isZh ? `开始测试 ${provider.name}...` : `Start testing ${provider.name}...`);
      appendTestLog("info", isZh ? "▶ 连通性检测" : "▶ Connectivity check");
      appendTestLog("info", `→ ${provider.base_url}`);

      const connectivity = await backend<TestResult>("test_provider", { id: provider.id });
      if (isCanceled()) return;

      if (!connectivity.success) {
        const reason = connectivity.error ?? (isZh ? "连接失败" : "Connectivity check failed");
        finish(
          {
            success: false,
            latency_ms: connectivity.latency_ms ?? 0,
            model: undefined,
            error: reason,
          },
          `${isZh ? "✗ 连通性检测失败" : "✗ Connectivity check failed"}: ${reason}`,
          "error",
        );
        return;
      }

      appendTestLog(
        "success",
        `${isZh ? "✓ 连接成功，响应" : "✓ Connectivity ok, latency"} ${connectivity.latency_ms}ms`,
      );

      const modelsSource = provider.models_source?.trim() || provider.models_endpoint?.trim();
      if (!modelsSource) {
        finish(
          { success: true, latency_ms: connectivity.latency_ms, model: undefined, error: undefined },
          isZh ? "✓ 未配置模型发现源，测试完成" : "✓ Model discovery source not configured, test finished",
          "success",
        );
        return;
      }

      appendTestLog("info", isZh ? "▶ 获取模型列表" : "▶ Fetch model list");
      appendTestLog("info", `→ ${modelsSource}`);

      const models = await backend<string[]>("test_provider_models", { id: provider.id });
      if (isCanceled()) return;

      if (!models.length) {
        finish(
          {
            success: false,
            latency_ms: connectivity.latency_ms,
            model: undefined,
            error: isZh ? "模型列表为空或格式异常" : "Model list is empty or malformed",
          },
          isZh ? "✗ 模型列表为空或格式异常" : "✗ Model list is empty or malformed",
          "error",
        );
        return;
      }

      appendTestLog(
        "success",
        `${isZh ? "✓ 认证通过，获取到" : "✓ Auth valid, fetched"} ${models.length} ${isZh ? "个模型" : "models"}`,
      );
      models.forEach((model) => appendTestLog("info", `· ${model}`));

      finish(
        {
          success: true,
          latency_ms: connectivity.latency_ms,
          model: models[0],
          error: undefined,
        },
        isZh ? "✓ 测试完成" : "✓ Test completed",
        "success",
      );
    } catch (error: unknown) {
      if (isCanceled()) return;
      const message = normalizeErrorMessage(error);
      finish(
        { success: false, latency_ms: 0, model: undefined, error: message },
        `${isZh ? "✗ 测试失败" : "✗ Test failed"}: ${message}`,
        "error",
      );
    }
  }

  function startEdit(p: Provider) {
    setEditingId(p.id);
    setShowEditApiKey(false);
    setEditForm({
      id: p.id,
      name: p.name,
      vendor: p.vendor ?? (p.preset_key || undefined),
      protocol: p.protocol,
      base_url: p.base_url,
      preset_key: p.preset_key || DEFAULT_PRESET_ID,
      channel: p.channel || "default",
      models_endpoint: p.models_endpoint ?? "",
      models_source: p.models_source ?? p.models_endpoint ?? "",
      capabilities_source: p.capabilities_source ?? "",
      static_models: p.static_models ?? "",
      api_key: p.api_key ?? "",
    });
  }

  function handlePresetChange(nextPresetId: string) {
    if (!nextPresetId) return;
    setSelectedPresetId(nextPresetId);
    const preset = providerPresets.find((item) => item.id === nextPresetId);
    if (!preset) return;

    const nextChannelId = preset.channels?.[0]?.id ?? "";
    const nextProtocol = resolvePresetProtocol(preset, nextChannelId, preset.defaultProtocol);
    const config = resolvePresetConfig(preset, nextProtocol, nextChannelId);

    setForm((prev) => ({
      ...prev,
      vendor: preset.id === DEFAULT_PRESET_ID ? undefined : preset.id,
      protocol: nextProtocol,
      base_url: config.baseUrl,
      preset_key: preset.id,
      channel: nextChannelId,
      models_source: config.modelsSource,
      models_endpoint: config.modelsSource,
      capabilities_source: config.capabilitiesSource,
      static_models: config.staticModels,
      api_key: config.apiKey || prev.api_key,
    }));
  }

  function handlePresetChannelChange(nextChannelId: string) {
    if (!selectedPreset) return;
    const nextProtocol = resolvePresetProtocol(
      selectedPreset,
      nextChannelId,
      form.protocol as ProviderProtocol,
    );
    const config = resolvePresetConfig(selectedPreset, nextProtocol, nextChannelId);
    setForm((prev) => ({
      ...prev,
      channel: nextChannelId,
      protocol: nextProtocol,
      base_url: config.baseUrl,
      models_source: config.modelsSource,
      models_endpoint: config.modelsSource,
      capabilities_source: config.capabilitiesSource,
      static_models: config.staticModels,
      api_key: config.apiKey || prev.api_key,
    }));
  }

  function handleEditPresetChange(nextPresetId: string) {
    if (!nextPresetId) return;
    const preset = providerPresets.find((item) => item.id === nextPresetId);
    if (!preset) return;

    const nextChannelId = preset.channels?.[0]?.id ?? "";
    setEditForm((prev) =>
      prev
        ? (() => {
            const nextProtocol = resolvePresetProtocol(
              preset,
              nextChannelId,
              (prev.protocol as ProviderProtocol) || preset.defaultProtocol,
            );
            const config = resolvePresetConfig(preset, nextProtocol, nextChannelId);
            return {
              ...prev,
              vendor: preset.id === DEFAULT_PRESET_ID ? undefined : preset.id,
              preset_key: preset.id,
              channel: nextChannelId,
              protocol: nextProtocol,
              base_url: config.baseUrl,
              models_source: config.modelsSource,
              models_endpoint: config.modelsSource,
              capabilities_source: config.capabilitiesSource,
              static_models: config.staticModels,
              api_key: config.apiKey || prev.api_key,
            };
          })()
        : prev,
    );
  }

  function closeCreateForm() {
    setShowForm(false);
    setShowCreateApiKey(true);
    setSelectedPresetId(DEFAULT_PRESET_ID);
    setForm(emptyCreate);
  }

  const totalPages = Math.max(1, Math.ceil(providers.length / PAGE_SIZE));
  const pagedProviders = providers.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);
  const createChannelOptions = selectedPreset ? presetChannels(selectedPreset) : [fallbackChannelPreset()];
  const createChannelValue =
    selectedPreset?.channels?.length
      ? (form.channel || createChannelOptions[0]?.id || "")
      : (createChannelOptions[0]?.id ?? "default");
  const createProtocolOptions = protocolOptions.filter((option) =>
    availableProtocolsForPreset(selectedPreset, createChannelValue).includes(option.value),
  );

  useEffect(() => {
    if (page > totalPages - 1) {
      setPage(0);
    }
  }, [page, totalPages]);

  useEffect(() => {
    if (!logsContainerRef.current) return;
    logsContainerRef.current.scrollTop = logsContainerRef.current.scrollHeight;
  }, [testLogs]);

  useEffect(() => {
    saveProviderTestResults(testResult);
  }, [testResult]);

  useEffect(() => {
    if (isLoading) return;
    const validIds = new Set(providers.map((provider) => provider.id));
    setTestResult((prev) => {
      let changed = false;
      const next: Record<string, TestResult> = {};
      for (const [id, result] of Object.entries(prev)) {
        if (validIds.has(id)) {
          next[id] = result;
        } else {
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [isLoading, providers]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">{isZh ? "提供商" : "Providers"}</h1>
          <p className="mt-1 text-sm text-slate-500">
            {isZh ? "管理你的 LLM 提供商连接" : "Manage your LLM provider connections"}
          </p>
        </div>
        <Button
          onClick={() => {
            setEditingId(null);
            if (showForm) {
              closeCreateForm();
              return;
            }
            setShowForm(true);
            setShowCreateApiKey(true);
            handlePresetChange(DEFAULT_PRESET_ID);
          }}
          className="flex items-center gap-2"
        >
          <Plus className="h-4 w-4" />
          {isZh ? "新增提供商" : "Add Provider"}
        </Button>
      </div>

      {/* Create Form */}
      {showForm && (
        <div className="glass rounded-2xl p-6 space-y-6">
          <h2 className="text-lg font-semibold text-slate-900">{isZh ? "新建提供商" : "New Provider"}</h2>
          <div className="space-y-3">
            <div>
              <p className="text-sm font-semibold text-slate-700">
                {isZh ? "1. 快速选择常用模型供应商（可选）" : "1. Quick Select A Common Provider (Optional)"}
              </p>
              <p className="mt-1 text-xs text-slate-500">
                {isZh
                  ? "选择预设后会自动填充默认配置，后续可继续手动修改。"
                  : "Selecting a preset prefills default values, and you can still edit them."}
              </p>
            </div>
            <ToggleGroup
              type="single"
              value={selectedPresetId}
              onValueChange={handlePresetChange}
              className="provider-preset-group"
            >
              {[...providerPresets]
                .sort((a, b) => (a.id === DEFAULT_PRESET_ID ? -1 : b.id === DEFAULT_PRESET_ID ? 1 : 0))
                .map((preset) => (
                <ToggleGroupItem
                  key={preset.id}
                  value={preset.id}
                  variant="outline"
                  size="lg"
                  className="provider-preset-card h-auto w-full flex-col gap-3 px-4 py-5"
                  aria-label={presetLabel(preset, isZh)}
                >
                  {preset.icon === "nyro" ? (
                    <>
                      <NyroIcon
                        size={26}
                        className="provider-preset-icon provider-preset-icon-custom provider-preset-icon-colored"
                      />
                      <NyroIcon
                        size={26}
                        monochrome
                        className="provider-preset-icon provider-preset-icon-custom provider-preset-icon-mono"
                      />
                    </>
                  ) : (
                    <>
                      <ProviderIcon
                        name={preset.icon ?? preset.label.en}
                        size={26}
                        className="provider-preset-icon provider-preset-icon-colored rounded-none border-0 bg-transparent"
                      />
                      <ProviderIcon
                        name={preset.icon ?? preset.label.en}
                        size={26}
                        monochrome
                        className="provider-preset-icon provider-preset-icon-mono rounded-none border-0 bg-transparent"
                      />
                    </>
                  )}
                  <span className={presetLabelClass(preset, isZh)}>{presetLabel(preset, isZh)}</span>
                </ToggleGroupItem>
              ))}
            </ToggleGroup>
          </div>
          <div className="h-px bg-slate-200/70" />
          <div className="space-y-4">
            <div>
              <p className="text-sm font-semibold text-slate-700">
                {isZh ? "2. 基础信息" : "2. Basic Information"}
              </p>
              <p className="mt-1 text-xs text-slate-500">
                {selectedPreset
                  ? (isZh
                    ? `已套用 ${presetLabel(selectedPreset, true)} 预设，可继续修改。`
                    : `${presetLabel(selectedPreset, false)} preset applied. You can continue editing.`)
                  : (isZh
                    ? "也可以跳过第一步，直接手动填写。"
                    : "You can also skip step one and fill everything manually.")}
              </p>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="col-span-2 space-y-2">
                <ToggleGroup
                  type="single"
                  value={createChannelValue}
                  onValueChange={(value) => {
                    if (!value || !selectedPreset?.channels?.length) return;
                    handlePresetChannelChange(value);
                  }}
                  className="provider-channel-group"
                >
                  {createChannelOptions.map((channel) => (
                    <ToggleGroupItem
                      key={channel.id}
                      value={channel.id}
                      variant="outline"
                      size="default"
                      className="provider-preset-card provider-channel-item"
                    >
                      {channelLabel(channel, isZh)}
                    </ToggleGroupItem>
                  ))}
                </ToggleGroup>
              </div>
              <div className="space-y-2">
                <FieldLabel>{isZh ? "名称" : "Name"}</FieldLabel>
                <Input
                  placeholder={isZh ? "例如 OpenAI 生产" : "e.g. OpenAI Production"}
                  value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <FieldLabel>{isZh ? "协议" : "Protocol"}</FieldLabel>
                <Select
                  value={form.protocol}
                  onValueChange={(value) => {
                    const nextProtocol = value as ProviderProtocol;
                    const config = selectedPreset
                      ? resolvePresetConfig(selectedPreset, nextProtocol, form.channel)
                      : {
                          baseUrl: protocolUrl(nextProtocol),
                          modelsSource: defaultModelsEndpoint(protocolUrl(nextProtocol), nextProtocol),
                          capabilitiesSource: "",
                          staticModels: form.static_models ?? "",
                        };
                    const nextBaseUrl =
                      selectedPreset && selectedPreset.id !== DEFAULT_PRESET_ID
                        ? (config.baseUrl || form.base_url)
                        : config.baseUrl;
                    setForm({
                      ...form,
                      protocol: nextProtocol,
                      base_url: nextBaseUrl,
                      // models_source should be filled by preset selection,
                      // and should not be auto-updated when only protocol changes.
                      models_source: form.models_source,
                      models_endpoint: form.models_source,
                      capabilities_source: config.capabilitiesSource,
                      static_models: config.staticModels,
                    });
                  }}
                >
                  <SelectTrigger>
                    <SelectValue placeholder={isZh ? "选择协议" : "Select protocol"} />
                  </SelectTrigger>
                  <SelectContent>
                    {createProtocolOptions.map((option) => (
                      <SelectItem key={option.value} value={option.value}>
                        {option.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <FieldLabel>{isZh ? "Base URL" : "Base URL"}</FieldLabel>
                <Input
                  placeholder={isZh ? "输入上游基础地址" : "Enter upstream base URL"}
                  value={form.base_url}
                  onChange={(e) => setForm({ ...form, base_url: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <FieldLabel>API Key</FieldLabel>
                <div className="relative">
                  <Input
                    placeholder="sk-..."
                    type={showCreateApiKey ? "text" : "password"}
                    value={form.api_key}
                    className="pr-10"
                    onChange={(e) => setForm({ ...form, api_key: e.target.value })}
                  />
                  <button
                    type="button"
                    onClick={() => setShowCreateApiKey((prev) => !prev)}
                    className="absolute top-1/2 right-3 -translate-y-1/2 text-slate-400 hover:text-slate-600 cursor-pointer"
                    aria-label={showCreateApiKey ? (isZh ? "隐藏 API Key" : "Hide API key") : (isZh ? "显示 API Key" : "Show API key")}
                  >
                    {showCreateApiKey ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>
              <div className="space-y-2">
                <FieldLabel
                  info={
                    isZh
                      ? "用于创建路由时自动获取可用模型列表"
                      : "Used to auto-fetch available model list when creating routes"
                  }
                >
                  {isZh ? "模型发现源" : "Model Discovery Source"}
                </FieldLabel>
                <Input
                  placeholder={isZh ? "可选，支持 https:// 或 ai://models.dev/..." : "Optional, supports https:// or ai://models.dev/..."}
                  value={form.models_source ?? form.models_endpoint ?? ""}
                  onChange={(e) => setForm({ ...form, models_source: e.target.value, models_endpoint: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <FieldLabel
                  info={
                    isZh
                      ? "用于识别模型能力，自动处理请求转发与 CLI 配置生成"
                      : "Used to identify model capabilities and auto-handle forwarding and CLI config generation"
                  }
                >
                  {isZh ? "能力发现源" : "Capability Discovery Source"}
                </FieldLabel>
                <Input
                  placeholder={isZh ? "可选，支持 https:// 或 ai://models.dev/..." : "Optional, supports https:// or ai://models.dev/..."}
                  value={form.capabilities_source ?? ""}
                  onChange={(e) => setForm({ ...form, capabilities_source: e.target.value })}
                />
              </div>
            </div>
            <div className="flex gap-3">
              <Button
                onClick={() => createMut.mutate(form)}
                disabled={createMut.isPending || !form.name || !form.api_key}
              >
                {createMut.isPending ? (isZh ? "创建中..." : "Creating...") : (isZh ? "创建" : "Create")}
              </Button>
              <Button
                onClick={closeCreateForm}
                variant="secondary"
              >
                {isZh ? "取消" : "Cancel"}
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* List */}
      {isLoading ? (
        <div className="text-center text-sm text-slate-500 py-12">{isZh ? "加载中..." : "Loading..."}</div>
      ) : providers.length === 0 ? (
        <div className="glass rounded-2xl p-12 text-center">
          <Server className="mx-auto h-10 w-10 text-slate-400" />
          <p className="mt-3 text-sm text-slate-500">{isZh ? "还没有配置提供商" : "No providers configured yet"}</p>
          <p className="mt-1 text-xs text-slate-400">{isZh ? "添加提供商后开始使用" : "Add a provider to get started"}</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {pagedProviders.map((p) => {
            const tr = testResult[p.id];
            const status = tr ? (tr.success ? "success" : "failed") : null;
            const isEditing = editingId === p.id;
            const editingPresetId = editForm.preset_key || DEFAULT_PRESET_ID;
            const editingPreset =
              providerPresets.find((preset) => preset.id === editingPresetId) ?? providerPresets[0] ?? null;

            if (isEditing) {
              const editingChannelOptions = presetChannels(editingPreset);
              const editingChannelValue =
                editingPreset?.channels?.length
                  ? (editForm.channel || editingChannelOptions[0]?.id || "")
                  : (editingChannelOptions[0]?.id ?? "default");
              const editingProtocolOptions = protocolOptions.filter((option) =>
                availableProtocolsForPreset(editingPreset, editingChannelValue).includes(option.value),
              );
              return (
                <div key={p.id} className="glass rounded-2xl p-5 space-y-4">
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-semibold text-slate-900">{isZh ? "编辑提供商" : "Edit Provider"}</h3>
                    <button onClick={() => setEditingId(null)} className="p-1 text-slate-400 hover:text-slate-600 cursor-pointer">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                  <div className="space-y-3">
                    <p className="text-sm font-semibold text-slate-700">
                      {isZh ? "1. 供应商" : "1. Provider"}
                    </p>
                    <ToggleGroup
                      type="single"
                      value={editingPresetId}
                      onValueChange={handleEditPresetChange}
                      className="provider-preset-group"
                    >
                      {[...providerPresets]
                        .sort((a, b) => (a.id === DEFAULT_PRESET_ID ? -1 : b.id === DEFAULT_PRESET_ID ? 1 : 0))
                        .map((preset) => (
                        <ToggleGroupItem
                          key={preset.id}
                          value={preset.id}
                          variant="outline"
                          size="lg"
                          className="provider-preset-card h-auto w-full flex-col gap-3 px-4 py-5"
                          aria-label={presetLabel(preset, isZh)}
                        >
                          {preset.icon === "nyro" ? (
                            <>
                              <NyroIcon
                                size={26}
                                className="provider-preset-icon provider-preset-icon-custom provider-preset-icon-colored"
                              />
                              <NyroIcon
                                size={26}
                                monochrome
                                className="provider-preset-icon provider-preset-icon-custom provider-preset-icon-mono"
                              />
                            </>
                          ) : (
                            <>
                              <ProviderIcon
                                name={preset.icon ?? preset.label.en}
                                size={26}
                                className="provider-preset-icon provider-preset-icon-colored rounded-none border-0 bg-transparent"
                              />
                              <ProviderIcon
                                name={preset.icon ?? preset.label.en}
                                size={26}
                                monochrome
                                className="provider-preset-icon provider-preset-icon-mono rounded-none border-0 bg-transparent"
                              />
                            </>
                          )}
                          <span className={presetLabelClass(preset, isZh)}>{presetLabel(preset, isZh)}</span>
                        </ToggleGroupItem>
                      ))}
                    </ToggleGroup>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="col-span-2 space-y-2">
                      <FieldLabel>{isZh ? "渠道" : "Channel"}</FieldLabel>
                      <ToggleGroup
                        type="single"
                        value={editingChannelValue}
                        onValueChange={(value) => {
                          if (!value || !editingPreset?.channels?.length) return;
                          const config = resolvePresetConfig(
                            editingPreset,
                            resolvePresetProtocol(
                              editingPreset,
                              value,
                              (editForm.protocol as ProviderProtocol) || editingPreset.defaultProtocol,
                            ),
                            value,
                          );
                          setEditForm({
                            ...editForm,
                            channel: value,
                            protocol: resolvePresetProtocol(
                              editingPreset,
                              value,
                              (editForm.protocol as ProviderProtocol) || editingPreset.defaultProtocol,
                            ),
                            base_url: config.baseUrl,
                            models_source: config.modelsSource,
                            models_endpoint: config.modelsSource,
                            capabilities_source: config.capabilitiesSource,
                            static_models: config.staticModels,
                          });
                        }}
                        className="provider-channel-group"
                      >
                        {editingChannelOptions.map((channel) => (
                          <ToggleGroupItem
                            key={channel.id}
                            value={channel.id}
                            variant="outline"
                            size="default"
                            className="provider-preset-card provider-channel-item"
                          >
                            {channelLabel(channel, isZh)}
                          </ToggleGroupItem>
                        ))}
                      </ToggleGroup>
                    </div>
                    <div className="space-y-2">
                      <FieldLabel>{isZh ? "名称" : "Name"}</FieldLabel>
                      <Input
                        placeholder={isZh ? "提供商名称" : "Provider name"}
                        value={editForm.name ?? ""}
                        onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <FieldLabel>{isZh ? "协议" : "Protocol"}</FieldLabel>
                      <Select
                        value={editForm.protocol ?? ""}
                        onValueChange={(value) => {
                          const nextProtocol = value as ProviderProtocol;
                          const config = editingPreset
                            ? resolvePresetConfig(editingPreset, nextProtocol, editForm.channel ?? undefined)
                            : {
                                baseUrl: protocolUrl(nextProtocol),
                                modelsSource: defaultModelsEndpoint(protocolUrl(nextProtocol), nextProtocol),
                                capabilitiesSource: "",
                                staticModels: editForm.static_models ?? "",
                              };
                          const nextBaseUrl =
                            editingPreset && editingPreset.id !== DEFAULT_PRESET_ID
                              ? (config.baseUrl || editForm.base_url || "")
                              : config.baseUrl;
                          setEditForm({
                            ...editForm,
                            protocol: nextProtocol,
                            base_url: nextBaseUrl,
                            // Keep user/preset selected model discovery source stable
                            // when protocol changes.
                            models_source: editForm.models_source,
                            models_endpoint: editForm.models_source,
                            capabilities_source: config.capabilitiesSource,
                            static_models: config.staticModels,
                          });
                        }}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder={isZh ? "选择协议" : "Select protocol"} />
                        </SelectTrigger>
                        <SelectContent>
                          {editingProtocolOptions.map((option) => (
                            <SelectItem key={option.value} value={option.value}>
                              {option.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-2">
                      <FieldLabel>{isZh ? "Base URL" : "Base URL"}</FieldLabel>
                      <Input
                        placeholder={isZh ? "输入上游基础地址" : "Enter upstream base URL"}
                        value={editForm.base_url ?? ""}
                        onChange={(e) => setEditForm({ ...editForm, base_url: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <FieldLabel>{isZh ? "API Key" : "API Key"}</FieldLabel>
                      <div className="relative">
                        <Input
                          placeholder="sk-..."
                          type={showEditApiKey ? "text" : "password"}
                          value={editForm.api_key ?? ""}
                          className="pr-10"
                          onChange={(e) => setEditForm({ ...editForm, api_key: e.target.value })}
                        />
                        <button
                          type="button"
                          onClick={() => setShowEditApiKey((prev) => !prev)}
                          className="absolute top-1/2 right-3 -translate-y-1/2 text-slate-400 hover:text-slate-600 cursor-pointer"
                          aria-label={showEditApiKey ? (isZh ? "隐藏 API Key" : "Hide API key") : (isZh ? "显示 API Key" : "Show API key")}
                        >
                          {showEditApiKey ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </div>
                    <div className="space-y-2">
                      <FieldLabel
                        info={
                          isZh
                            ? "用于创建路由时自动获取可用模型列表"
                            : "Used to auto-fetch available model list when creating routes"
                        }
                      >
                        {isZh ? "模型发现源" : "Model Discovery Source"}
                      </FieldLabel>
                      <Input
                        placeholder={isZh ? "可选，支持 https:// 或 ai://models.dev/..." : "Optional, supports https:// or ai://models.dev/..."}
                        value={editForm.models_source ?? editForm.models_endpoint ?? ""}
                        onChange={(e) => setEditForm({ ...editForm, models_source: e.target.value, models_endpoint: e.target.value })}
                      />
                    </div>
                    <div className="space-y-2">
                      <FieldLabel
                        info={
                          isZh
                            ? "用于识别模型能力，自动处理请求转发与 CLI 配置生成"
                            : "Used to identify model capabilities and auto-handle forwarding and CLI config generation"
                        }
                      >
                        {isZh ? "能力发现源" : "Capability Discovery Source"}
                      </FieldLabel>
                      <Input
                        placeholder={isZh ? "可选，支持 https:// 或 ai://models.dev/..." : "Optional, supports https:// or ai://models.dev/..."}
                        value={editForm.capabilities_source ?? ""}
                        onChange={(e) => setEditForm({ ...editForm, capabilities_source: e.target.value })}
                      />
                    </div>
                  </div>
                  <div className="flex gap-3">
                    <Button
                      onClick={() => {
                        setEditError(null);
                        const input: UpdateProvider = {
                          name: editForm.name || undefined,
                          vendor: editForm.vendor || undefined,
                          protocol: editForm.protocol || undefined,
                          base_url: editForm.base_url || undefined,
                          preset_key: editForm.preset_key || undefined,
                          channel: editForm.channel || undefined,
                          models_endpoint: editForm.models_endpoint || undefined,
                          models_source: editForm.models_source || undefined,
                          capabilities_source: editForm.capabilities_source || undefined,
                          static_models: editForm.static_models || undefined,
                          api_key: editForm.api_key || undefined,
                        };
                        updateMut.mutate({ id: editForm.id, ...input });
                      }}
                      disabled={updateMut.isPending}
                    >
                      {updateMut.isPending ? (isZh ? "保存中..." : "Saving...") : (isZh ? "保存" : "Save")}
                    </Button>
                    <Button
                      onClick={() => { setEditingId(null); setEditError(null); }}
                      variant="secondary"
                    >
                      {isZh ? "取消" : "Cancel"}
                    </Button>
                  </div>
                  {editError && (
                    <p className="text-xs text-red-600 bg-red-50 rounded-lg px-3 py-2">{editError}</p>
                  )}
                </div>
              );
            }

            return (
              <div key={p.id} className="glass rounded-2xl p-5">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-slate-100">
                      <ProviderIcon
                        name={p.name}
                        protocol={p.protocol}
                        baseUrl={p.base_url}
                        size={34}
                        className="provider-preset-icon provider-preset-icon-colored rounded-xl border border-slate-300/70 bg-transparent"
                      />
                      <ProviderIcon
                        name={p.name}
                        protocol={p.protocol}
                        baseUrl={p.base_url}
                        size={34}
                        monochrome
                        className="provider-preset-icon provider-preset-icon-mono rounded-xl border border-slate-300/70 bg-transparent"
                      />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-slate-900">{p.name}</span>
                        <span className="protocol-pill inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-medium uppercase">
                          {p.protocol}
                        </span>
                        {status === "success" ? (
                          <CheckCircle
                            className="h-3.5 w-3.5 text-green-500"
                            aria-label={isZh ? "测试成功" : "Test passed"}
                          />
                        ) : status === "failed" ? (
                          <XCircle
                            className="h-3.5 w-3.5 text-red-400"
                            aria-label={isZh ? "测试失败" : "Test failed"}
                          />
                        ) : null}
                      </div>
                      <p className="mt-0.5 text-xs text-slate-500">{p.base_url}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-0.5">
                    <button
                      onClick={() => handleTest(p)}
                      disabled={Boolean(testingId)}
                      title={isZh ? "测试" : "Test"}
                      className="rounded-lg p-2 text-slate-400 transition-colors hover:bg-amber-50 hover:text-amber-500 cursor-pointer disabled:opacity-50"
                    >
                      {testingId === p.id ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : (
                        <Zap className="h-3.5 w-3.5" />
                      )}
                    </button>
                    <button
                      onClick={() => startEdit(p)}
                      className="rounded-lg p-2 text-slate-400 transition-colors hover:bg-blue-50 hover:text-blue-500 cursor-pointer"
                    >
                      <Pencil className="h-4 w-4" />
                    </button>
                    <button
                      onClick={() => setProviderToDelete(p)}
                      className="rounded-lg p-2 text-slate-400 transition-colors hover:bg-red-50 hover:text-red-500 cursor-pointer"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>
            );
          })}

          {providers.length > PAGE_SIZE && (
            <div className="flex items-center justify-between px-1 pt-1">
              <span className="text-xs text-slate-500">
                {isZh ? `第 ${page + 1} / ${totalPages} 页` : `Page ${page + 1} of ${totalPages}`}
              </span>
              <div className="flex gap-1">
                <Button
                  onClick={() => setPage(Math.max(0, page - 1))}
                  disabled={page === 0}
                  variant="outline"
                  size="icon"
                >
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <Button
                  onClick={() => setPage(Math.min(totalPages - 1, page + 1))}
                  disabled={page >= totalPages - 1}
                  variant="outline"
                  size="icon"
                >
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          )}
        </div>
      )}

      <Dialog
        open={testDialogOpen}
        onOpenChange={(open) => {
          if (!open) {
            closeTestDialog();
          } else {
            setTestDialogOpen(true);
          }
        }}
      >
        <DialogContent className="w-[min(92vw,720px)]">
          <DialogHeader>
            <DialogTitle>
              {isZh ? `测试 ${testTarget?.name ?? ""}` : `Test ${testTarget?.name ?? ""}`}
            </DialogTitle>
            <DialogDescription>
              {isZh ? "实时展示 Provider 测试日志" : "Real-time logs for provider testing"}
            </DialogDescription>
          </DialogHeader>
          <div
            ref={logsContainerRef}
            className="h-64 overflow-y-auto rounded-lg border border-emerald-500/30 bg-[#050c1f] p-3 font-mono text-sm text-emerald-300 shadow-inner shadow-black/40"
          >
            {testLogs.length === 0 ? (
              <p className="text-xs text-emerald-400/80">{isZh ? "等待测试开始..." : "Waiting for test to start..."}</p>
            ) : (
              testLogs.map((log, idx) => (
                <p
                  key={`${log.timestamp}-${idx}`}
                  className={
                    log.level === "error"
                      ? "text-red-300"
                      : log.level === "success"
                        ? "text-emerald-300"
                        : "text-emerald-200"
                  }
                >
                  [{log.timestamp}] {log.message}
                </p>
              ))
            )}
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={closeTestDialog}>
              {isTestRunning
                ? (isZh ? "取消" : "Cancel")
                : (isZh ? "关闭" : "Close")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={Boolean(providerToDelete)}
        onOpenChange={(open) => {
          if (!open) setProviderToDelete(null);
        }}
        title={isZh ? "确认删除提供商" : "Confirm provider deletion"}
        description={
          providerToDelete
            ? (isZh
              ? `此操作不可撤销。确认删除「${providerToDelete.name}」吗？`
              : `This action cannot be undone. Delete "${providerToDelete.name}"?`)
            : undefined
        }
        cancelText={isZh ? "取消" : "Cancel"}
        confirmText={isZh ? "删除" : "Delete"}
        onConfirm={() => {
          if (!providerToDelete) return;
          deleteMut.mutate(providerToDelete.id);
          setProviderToDelete(null);
        }}
      />
      <ConfirmDialog
        open={Boolean(errorDialog)}
        onOpenChange={(open) => {
          if (!open) setErrorDialog(null);
        }}
        title={errorDialog?.title ?? ""}
        description={errorDialog?.description}
        hideCancel
        confirmText={isZh ? "我知道了" : "OK"}
        onConfirm={() => setErrorDialog(null)}
      />
    </div>
  );
}
