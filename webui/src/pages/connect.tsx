import { Suspense, lazy, useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Copy, Loader2, TerminalSquare, Wrench } from "lucide-react";

import { backend, IS_TAURI } from "@/lib/backend";
import { localizeBackendErrorMessage } from "@/lib/backend-error";
import type { ApiKey, GatewayStatus, ModelCapabilities, Route as RouteType } from "@/lib/types";
import { useLocale } from "@/lib/i18n";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { ProviderIcon } from "@/components/ui/provider-icon";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";

const CodeHighlighter = lazy(() => import("@/components/ui/code-highlighter"));

type CodeLanguage = "python" | "typescript" | "curl";
type CliToolId = "claude-code" | "codex-cli" | "gemini-cli" | "opencode";

type CliTool = {
  id: CliToolId;
  name: string;
  iconKey: string;
  protocol: "openai" | "anthropic" | "gemini";
  desc: { zh: string; en: string };
};

const CLI_TOOLS: CliTool[] = [
  {
    id: "claude-code",
    name: "Claude Code",
    iconKey: "claude",
    protocol: "anthropic",
    desc: { zh: "Anthropic 官方命令行编程助手", en: "Anthropic official coding CLI assistant" },
  },
  {
    id: "codex-cli",
    name: "Codex CLI",
    iconKey: "openai",
    protocol: "openai",
    desc: { zh: "OpenAI 命令行编程工具", en: "OpenAI coding CLI tool" },
  },
  {
    id: "gemini-cli",
    name: "Gemini CLI",
    iconKey: "gemini",
    protocol: "gemini",
    desc: { zh: "Google Gemini 命令行工具", en: "Google Gemini command line tool" },
  },
  {
    id: "opencode",
    name: "OpenCode",
    iconKey: "opencode-logo-light",
    protocol: "openai",
    desc: { zh: "开源 AI 编程命令行工具", en: "Open-source AI coding CLI tool" },
  },
];

const CODE_LANGS: CodeLanguage[] = ["python", "typescript", "curl"];
const OPTIONAL_KEY_PLACEHOLDER = "sk-00000000000000000000000000000000";
const UNSELECTED_KEY_PLACEHOLDER = "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";

function maskApiKey(key: string) {
  if (key.length <= 14) return key;
  return `${key.slice(0, 12)}••`;
}

function protocolLabel(protocol: RouteType["ingress_protocol"], isZh: boolean) {
  if (isZh) {
    if (protocol === "openai") return "OpenAI 协议";
    if (protocol === "anthropic") return "Anthropic 协议";
    return "Gemini 协议";
  }
  if (protocol === "openai") return "OpenAI";
  if (protocol === "anthropic") return "Anthropic";
  return "Gemini";
}

function jsonText(input: unknown) {
  return JSON.stringify(input, null, 2);
}

function encodeGeminiModelForPath(model: string) {
  // Keep ":" readable for model variants like gemma3:1b.
  return encodeURIComponent(model).replace(/%3A/gi, ":");
}

function codeTemplate(params: {
  protocol: RouteType["ingress_protocol"];
  model: string;
  apiKey: string;
  host: string;
  language: CodeLanguage;
}) {
  const { protocol, model, apiKey, host, language } = params;

  if (language === "curl") {
    if (protocol === "openai") {
      return `curl ${host}/v1/chat/completions \\
  -H "Authorization: Bearer ${apiKey}" \\
  -H "Content-Type: application/json" \\
  -d '${jsonText({
    model,
    messages: [{ role: "user", content: "Hello" }],
  })}'`;
    }
    if (protocol === "anthropic") {
      return `curl ${host}/v1/messages \\
  -H "x-api-key: ${apiKey}" \\
  -H "anthropic-version: 2023-06-01" \\
  -H "Content-Type: application/json" \\
  -d '${jsonText({
    model,
    max_tokens: 1024,
    messages: [{ role: "user", content: "Hello" }],
  })}'`;
    }
    return `curl ${host}/v1beta/models/${encodeGeminiModelForPath(model)}:generateContent \\
  -H "x-goog-api-key: ${apiKey}" \\
  -H "Content-Type: application/json" \\
  -d '${jsonText({
    contents: [{ role: "user", parts: [{ text: "Hello" }] }],
  })}'`;
  }

  if (language === "python") {
    if (protocol === "openai") {
      return `# pip install openai
from openai import OpenAI

client = OpenAI(
    api_key="${apiKey}",
    base_url="${host}/v1"
)

response = client.chat.completions.create(
    model="${model}",
    messages=[{"role": "user", "content": "Hello"}]
)

print(response.choices[0].message.content)`;
    }
    if (protocol === "anthropic") {
      return `# pip install anthropic
from anthropic import Anthropic

client = Anthropic(
    api_key="${apiKey}",
    base_url="${host}"
)

response = client.messages.create(
    model="${model}",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}]
)

print(response.content[0].text)`;
    }
    return `# pip install google-genai
from google import genai

client = genai.Client(
    api_key="${apiKey}",
    http_options={"base_url": "${host}"}
)

response = client.models.generate_content(
    model="${model}",
    contents="Hello"
)

print(response.text)`;
  }

  if (protocol === "openai") {
    return `// npm install openai
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: "${apiKey}",
  baseURL: "${host}/v1",
});

const response = await client.chat.completions.create({
  model: "${model}",
  messages: [{ role: "user", content: "Hello" }],
});

console.log(response.choices[0]?.message?.content);`;
  }
  if (protocol === "anthropic") {
    return `// npm install @anthropic-ai/sdk
import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({
  apiKey: "${apiKey}",
  baseURL: "${host}",
});

const response = await client.messages.create({
  model: "${model}",
  max_tokens: 1024,
  messages: [{ role: "user", content: "Hello" }],
});

console.log(response.content[0]);`;
  }
  return `// npm install @google/genai
import { GoogleGenAI } from "@google/genai";

const client = new GoogleGenAI({
  apiKey: "${apiKey}",
  baseUrl: "${host}",
});

const response = await client.models.generateContent({
  model: "${model}",
  contents: "Hello",
});

console.log(response.text);`;
}

function syntaxLanguage(language: CodeLanguage) {
  if (language === "python") return "python";
  if (language === "typescript") return "typescript";
  return "bash";
}

function languageLabel(language: CodeLanguage) {
  if (language === "python") return "Python";
  if (language === "typescript") return "TypeScript";
  return "cURL";
}

function inferClaudeProfile(model: string) {
  const value = model.toLowerCase();
  if (value.includes("haiku")) return "haiku";
  if (value.includes("sonnet")) return "sonnet";
  return "opus";
}

function cliPreviewTemplate(params: {
  tool: CliTool;
  host: string;
  apiKey: string;
  model: string;
  capabilities?: ModelCapabilities | null;
}) {
  const { tool, host, apiKey, model, capabilities } = params;
  if (tool.id === "claude-code") {
    return `# ~/.claude/settings.json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${apiKey}",
    "ANTHROPIC_BASE_URL": "${host}",
    "ANTHROPIC_MODEL": "${model}",
    "ANTHROPIC_REASONING_MODEL": "${model}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${model}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${model}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${model}"
  },
  "model": "${inferClaudeProfile(model)}"
}`;
  }
  if (tool.id === "codex-cli") {
    const reasoningLine = capabilities?.reasoning ? 'model_reasoning_effort = "high"\n' : "";
    const contextLine = capabilities?.context_window
      ? `model_context_window = ${capabilities.context_window}\n`
      : "";
    return `# ~/.codex/auth.json
{
  "OPENAI_API_KEY": "${apiKey}"
}

# ~/.codex/config.toml
model_provider = "nyro"
model = "${model}"
${reasoningLine}${contextLine}model_catalog_json = "~/.codex/nyro-models.json"
disable_response_storage = true

[model_providers.nyro]
name = "Nyro Gateway"
base_url = "${host}/v1"
wire_api = "responses"
requires_openai_auth = true`;
  }
  if (tool.id === "gemini-cli") {
    return `# ~/.gemini/.env
GEMINI_API_KEY=${apiKey}
GEMINI_MODEL=${model}
GOOGLE_GEMINI_BASE_URL=${host}

# ~/.gemini/settings.json
{
  "security": {
    "auth": {
      "selectedType": "gemini-api-key"
    }
  }
}`;
  }
  return `# ~/.config/opencode/opencode.json
{
  "provider": {
    "nyro": {
      "name": "Nyro Gateway",
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "${apiKey}",
        "baseURL": "${host}/v1",
        "model": "${model}"
      },
      "models": {
        "${model}": {
          "name": "${model}"
        }
      }
    }
  }
}`;
}

export default function ConnectPage() {
  const { locale } = useLocale();
  const isZh = locale === "zh-CN";
  const qc = useQueryClient();

  const [tab, setTab] = useState<"code" | "cli">("code");
  const [codeLang, setCodeLang] = useState<CodeLanguage>("python");
  const [selectedRouteId, setSelectedRouteId] = useState("");
  const [selectedCodeKeyId, setSelectedCodeKeyId] = useState("");
  const [selectedCliKeyId, setSelectedCliKeyId] = useState("");
  const [selectedCliToolId, setSelectedCliToolId] = useState<CliToolId>("claude-code");
  const [copiedTarget, setCopiedTarget] = useState<"code" | "cli" | null>(null);
  const [isDarkTheme, setIsDarkTheme] = useState(false);
  const [cliActionMessage, setCliActionMessage] = useState<{
    kind: "success" | "error";
    text: string;
  } | null>(null);
  const [errorDialog, setErrorDialog] = useState<{ title: string; description?: string } | null>(null);

  const { data: routes = [] } = useQuery<RouteType[]>({
    queryKey: ["routes"],
    queryFn: () => backend("list_routes"),
  });
  const { data: apiKeys = [] } = useQuery<ApiKey[]>({
    queryKey: ["api-keys"],
    queryFn: () => backend("list_api_keys"),
  });
  const { data: status } = useQuery<GatewayStatus>({
    queryKey: ["gateway-status"],
    queryFn: () => backend("get_gateway_status"),
  });
  const { data: cliReadyStatus = {} } = useQuery<Partial<Record<CliToolId, boolean>>>({
    queryKey: ["connect-cli-ready-status"],
    queryFn: () => backend("detect_cli_tools"),
    enabled: IS_TAURI,
    staleTime: 30_000,
    refetchInterval: 30_000,
  });

  useEffect(() => {
    const root = document.documentElement;
    const syncTheme = () => setIsDarkTheme(root.getAttribute("data-theme") === "dark");
    syncTheme();
    const observer = new MutationObserver(syncTheme);
    observer.observe(root, { attributes: true, attributeFilter: ["data-theme"] });
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    setCliActionMessage(null);
  }, [selectedCliToolId]);

  useEffect(() => {
    if (selectedRouteId && !routes.some((route) => route.id === selectedRouteId)) {
      setSelectedRouteId("");
    }
  }, [routes, selectedRouteId]);

  const selectedRoute = useMemo(
    () => routes.find((route) => route.id === selectedRouteId) ?? null,
    [routes, selectedRouteId],
  );

  const codeAvailableKeys = useMemo(() => {
    if (!selectedRoute) return [];
    return apiKeys.filter((key) => key.route_ids.includes(selectedRoute.id));
  }, [apiKeys, selectedRoute]);

  useEffect(() => {
    if (!selectedRoute?.access_control) {
      setSelectedCodeKeyId("");
      return;
    }
    if (selectedCodeKeyId && !codeAvailableKeys.some((key) => key.id === selectedCodeKeyId)) {
      setSelectedCodeKeyId("");
    }
  }, [codeAvailableKeys, selectedCodeKeyId, selectedRoute]);

  const selectedApiKey = useMemo(
    () => codeAvailableKeys.find((key) => key.id === selectedCodeKeyId) ?? null,
    [codeAvailableKeys, selectedCodeKeyId],
  );

  const codeEffectiveApiKey =
    selectedRoute?.access_control ? selectedApiKey?.key ?? UNSELECTED_KEY_PLACEHOLDER : OPTIONAL_KEY_PLACEHOLDER;
  const host = `http://localhost:${status?.proxy_port ?? 3000}`;
  const codeModel = selectedRoute?.virtual_model ?? "gpt-4o";
  const codeProtocol = selectedRoute?.ingress_protocol ?? "openai";
  const selectedCliTool =
    CLI_TOOLS.find((tool) => tool.id === selectedCliToolId) ?? CLI_TOOLS.find((tool) => tool.id === "claude-code")!;
  const selectedCliReady = Boolean(cliReadyStatus[selectedCliTool.id]);
  const cliRoutes = useMemo(
    () => routes.filter((route) => route.ingress_protocol === selectedCliTool.protocol),
    [routes, selectedCliTool.protocol],
  );
  const selectedCliRoute = useMemo(
    () => cliRoutes.find((route) => route.id === selectedRouteId) ?? null,
    [cliRoutes, selectedRouteId],
  );
  const cliAvailableKeys = useMemo(() => {
    if (!selectedCliRoute) return [];
    return apiKeys.filter((key) => key.route_ids.includes(selectedCliRoute.id));
  }, [apiKeys, selectedCliRoute]);

  useEffect(() => {
    if (tab !== "cli") return;
    if (selectedRouteId && !cliRoutes.some((route) => route.id === selectedRouteId)) {
      setSelectedRouteId("");
    }
  }, [cliRoutes, selectedRouteId, selectedCliTool.id, tab]);

  useEffect(() => {
    if (!selectedCliRoute?.access_control) {
      setSelectedCliKeyId("");
      return;
    }
    if (selectedCliKeyId && !cliAvailableKeys.some((key) => key.id === selectedCliKeyId)) {
      setSelectedCliKeyId("");
    }
  }, [selectedCliRoute, selectedCliKeyId, cliAvailableKeys]);

  const selectedCliApiKey = useMemo(
    () => cliAvailableKeys.find((key) => key.id === selectedCliKeyId) ?? null,
    [cliAvailableKeys, selectedCliKeyId],
  );
  const { data: selectedCliCapabilities } = useQuery<ModelCapabilities | null>({
    queryKey: [
      "connect-cli-model-capabilities",
      selectedCliRoute?.target_provider,
      selectedCliRoute?.target_model,
    ],
    queryFn: async () => {
      if (!selectedCliRoute?.target_provider || !selectedCliRoute?.target_model.trim()) return null;
      try {
        return await backend<ModelCapabilities>("get_model_capabilities", {
          providerId: selectedCliRoute.target_provider,
          model: selectedCliRoute.target_model.trim(),
        });
      } catch {
        return null;
      }
    },
    enabled: Boolean(selectedCliRoute?.target_provider && selectedCliRoute?.target_model.trim()),
    staleTime: 60_000,
  });
  const cliEffectiveApiKey =
    selectedCliRoute?.access_control
      ? selectedCliApiKey?.key ?? UNSELECTED_KEY_PLACEHOLDER
      : OPTIONAL_KEY_PLACEHOLDER;
  const cliModel = selectedCliRoute?.virtual_model ?? "gpt-4o";
  const canSyncCli =
    IS_TAURI &&
    selectedCliReady &&
    Boolean(selectedCliRoute) &&
    (!selectedCliRoute?.access_control || Boolean(selectedCliApiKey));

  const generatedCode = codeTemplate({
    protocol: codeProtocol,
    model: codeModel,
    apiKey: codeEffectiveApiKey,
    host,
    language: codeLang,
  });
  const cliPreview = cliPreviewTemplate({
    tool: selectedCliTool,
    host,
    apiKey: cliEffectiveApiKey,
    model: cliModel,
    capabilities: selectedCliCapabilities,
  });
  const cliPreviewLang = "bash";

  function formatCliError(error: unknown) {
    const localized = localizeBackendErrorMessage(error, isZh);
    if (localized && localized !== "undefined" && localized !== "null") return localized;
    return isZh ? "操作失败，请重试" : "Operation failed, please retry";
  }

  const syncCliMut = useMutation({
    mutationFn: () =>
      backend<string[]>("sync_cli_config", {
        toolId: selectedCliTool.id,
        host,
        apiKey: cliEffectiveApiKey,
        model: cliModel,
        capabilities: selectedCliCapabilities
          ? {
              contextWindow: selectedCliCapabilities.context_window,
              reasoning: selectedCliCapabilities.reasoning,
            }
          : undefined,
      }),
    onSuccess: () => {
      setCliActionMessage({
        kind: "success",
        text: isZh ? `已同步 ${selectedCliTool.name} 配置` : `Synced ${selectedCliTool.name} config`,
      });
      qc.invalidateQueries({ queryKey: ["connect-cli-ready-status"] });
    },
    onError: (error) => {
      const message = formatCliError(error);
      setCliActionMessage({
        kind: "error",
        text: message,
      });
      setErrorDialog({
        title: isZh ? "同步配置失败" : "Failed to sync config",
        description: message,
      });
    },
  });

  const restoreCliMut = useMutation({
    mutationFn: () =>
      backend<string[]>("restore_cli_config", {
        toolId: selectedCliTool.id,
      }),
    onSuccess: (paths) => {
      setCliActionMessage({
        kind: "success",
        text: paths.length
          ? (isZh ? `已恢复 ${selectedCliTool.name} 原配置` : `Restored ${selectedCliTool.name} config`)
          : (isZh ? "没有可恢复的配置快照" : "No saved snapshot to restore"),
      });
    },
    onError: (error) => {
      const message = formatCliError(error);
      setCliActionMessage({
        kind: "error",
        text: message,
      });
      setErrorDialog({
        title: isZh ? "恢复配置失败" : "Failed to restore config",
        description: message,
      });
    },
  });

  async function copyText(text: string, target: "code" | "cli") {
    await navigator.clipboard.writeText(text);
    setCopiedTarget(target);
    setTimeout(() => setCopiedTarget(null), 1200);
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">{isZh ? "接入" : "Connect"}</h1>
        <p className="mt-1 text-sm text-slate-500">
          {isZh
            ? "通过代码或命令行工具将应用连接到 Nyro Gateway"
            : "Connect your app to Nyro Gateway via code or CLI tools"}
        </p>
      </div>

      <div className="connect-panel glass rounded-2xl p-5">
        <Tabs value={tab} onValueChange={(next) => setTab(next as "code" | "cli")} className="space-y-3">
          <TabsList className="h-11 w-fit rounded-xl px-1.5">
            <TabsTrigger className="h-9 min-w-[108px] text-sm font-semibold" value="code">
              {isZh ? "代码接入" : "Code"}
            </TabsTrigger>
            <TabsTrigger className="h-9 min-w-[108px] text-sm font-semibold" value="cli">
              {isZh ? "CLI 接入" : "CLI"}
            </TabsTrigger>
          </TabsList>

          <TabsContent value="code" className="!mt-1 space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <p className="ml-1 text-xs leading-none font-normal text-slate-900">
                  {isZh ? "选择路由" : "Select Route"}
                </p>
                <Select value={selectedRouteId} onValueChange={setSelectedRouteId}>
                  <SelectTrigger>
                    <SelectValue
                      placeholder={isZh ? "请先创建路由" : "Create route first"}
                    />
                  </SelectTrigger>
                  <SelectContent>
                    {routes.map((route) => (
                      <SelectItem key={route.id} value={route.id}>
                        {`${route.name} · ${protocolLabel(route.ingress_protocol, isZh)} · ${route.virtual_model}`}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {selectedRoute?.access_control && (
                <div className="space-y-2">
                  <p className="ml-1 text-xs leading-none font-normal text-slate-900">
                    {isZh ? "选择 API Key" : "Select API Key"}
                  </p>
                  <Select
                    value={selectedCodeKeyId}
                    onValueChange={setSelectedCodeKeyId}
                    disabled={!selectedRoute}
                  >
                    <SelectTrigger>
                      <SelectValue
                        placeholder={isZh ? "选择 API Key" : "Select API key"}
                      />
                    </SelectTrigger>
                    <SelectContent>
                      {codeAvailableKeys.map((key) => (
                        <SelectItem key={key.id} value={key.id}>
                          {`${key.name} · ${maskApiKey(key.key)}`}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>

            {selectedRoute && (
              <div className="space-y-2">
                <div className="connect-code-tabs flex gap-1">
                  {CODE_LANGS.map((lang) => (
                    <button
                      key={lang}
                      onClick={() => setCodeLang(lang)}
                      className={`connect-code-tab-btn px-3 py-2 text-xs font-medium transition-colors cursor-pointer ${
                        codeLang === lang ? "is-active" : ""
                      }`}
                    >
                      {languageLabel(lang)}
                    </button>
                  ))}
                </div>

                <div className="connect-code-example-box relative rounded-xl p-4">
                  <button
                    onClick={() => copyText(generatedCode, "code")}
                    className="connect-code-copy-btn absolute top-3 right-3 rounded-xl p-3 cursor-pointer transition-colors"
                    title={isZh ? "复制代码" : "Copy code"}
                  >
                    {copiedTarget === "code" ? <Check className="h-4 w-4 text-green-600" /> : <Copy className="h-4 w-4" />}
                  </button>
                  <Suspense fallback={<pre className="overflow-x-auto text-xs text-slate-500">{generatedCode}</pre>}>
                    <CodeHighlighter
                      code={generatedCode}
                      language={syntaxLanguage(codeLang)}
                      dark={isDarkTheme}
                      padding={0}
                    />
                  </Suspense>
                </div>
              </div>
            )}

            {selectedRoute && !selectedRoute.access_control && (
              <p className="text-xs text-slate-500">
                {isZh
                  ? `当前路由未开启访问控制，示例中已使用占位 API Key：${OPTIONAL_KEY_PLACEHOLDER}`
                  : `Access control is disabled on this route. The sample uses placeholder key: ${OPTIONAL_KEY_PLACEHOLDER}`}
              </p>
            )}
          </TabsContent>

          <TabsContent value="cli" className="!mt-1 space-y-4">
            {!IS_TAURI && (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-700">
                {isZh ? "CLI 接入仅桌面版可用。" : "CLI integration is desktop-only."}
              </div>
            )}

            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              {CLI_TOOLS.map((tool) => {
                const active = tool.id === selectedCliToolId;
                const isReady = Boolean(cliReadyStatus[tool.id]);
                return (
                  <button
                    key={tool.id}
                    type="button"
                    onClick={() => setSelectedCliToolId(tool.id)}
                    data-state={active ? "on" : "off"}
                    className="provider-preset-card connect-cli-tool-card h-auto w-full rounded-2xl text-left"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex items-start gap-3">
                        <div className="mt-0.5 inline-flex h-8 w-8 items-center justify-center">
                          <ProviderIcon
                            iconKey={tool.iconKey}
                            name={tool.name}
                            protocol={tool.protocol}
                            size={26}
                            className="provider-preset-icon provider-preset-icon-colored rounded-none border-0 bg-transparent"
                          />
                          <ProviderIcon
                            iconKey={tool.iconKey}
                            name={tool.name}
                            protocol={tool.protocol}
                            size={26}
                            monochrome
                            className="provider-preset-icon provider-preset-icon-mono rounded-none border-0 bg-transparent"
                          />
                        </div>
                        <div>
                          <p className="text-base leading-tight font-semibold text-slate-900">{tool.name}</p>
                          <p className="mt-1 text-sm text-slate-500">{isZh ? tool.desc.zh : tool.desc.en}</p>
                        </div>
                      </div>
                      <Badge variant={isReady ? "success" : "secondary"}>
                        {isReady ? (isZh ? "已就绪" : "Ready") : (isZh ? "未就绪" : "Not Ready")}
                      </Badge>
                    </div>
                  </button>
                );
              })}
            </div>

            {selectedCliReady ? (
              <div className="connect-cli-shell rounded-xl border p-4 space-y-3">
                <div className="flex items-center gap-2">
                  <TerminalSquare className="h-4 w-4 text-slate-600" />
                  <p className="text-sm font-semibold text-slate-800">{selectedCliTool.name}</p>
                  <Badge variant="outline">{protocolLabel(selectedCliTool.protocol, isZh)}</Badge>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <p className="ml-1 text-xs leading-none font-normal text-slate-900">
                      {isZh ? "选择路由" : "Select Route"}
                    </p>
                    <Select value={selectedRouteId} onValueChange={setSelectedRouteId}>
                      <SelectTrigger>
                        <SelectValue
                          placeholder={
                            cliRoutes.length > 0
                              ? (isZh ? "选择路由" : "Select route")
                              : (isZh ? "请先创建对应协议路由" : "Create matching protocol route first")
                          }
                        />
                      </SelectTrigger>
                      <SelectContent>
                        {cliRoutes.map((route) => (
                          <SelectItem key={route.id} value={route.id}>
                            {`${route.name} · ${protocolLabel(route.ingress_protocol, isZh)} · ${route.virtual_model}`}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  {selectedCliRoute?.access_control && (
                    <div className="space-y-2">
                      <p className="ml-1 text-xs leading-none font-normal text-slate-900">
                        {isZh ? "选择 API Key" : "Select API Key"}
                      </p>
                      <Select
                        value={selectedCliKeyId}
                        onValueChange={setSelectedCliKeyId}
                        disabled={!selectedCliRoute}
                      >
                        <SelectTrigger>
                          <SelectValue
                            placeholder={isZh ? "选择 API Key" : "Select API key"}
                          />
                        </SelectTrigger>
                        <SelectContent>
                          {cliAvailableKeys.map((key) => (
                            <SelectItem key={key.id} value={key.id}>
                              {`${key.name} · ${maskApiKey(key.key)}`}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}
                </div>

                <p className="text-xs text-slate-500">
                  {isZh ? "仅展示将被更新的配置片段" : "Only showing configuration fragments to be updated"}
                </p>
                {selectedCliCapabilities && (
                  <div className="flex flex-wrap gap-2 text-xs text-slate-600">
                    {selectedCliCapabilities.reasoning && <Badge variant="success">{isZh ? "推理" : "Reasoning"}</Badge>}
                    {selectedCliCapabilities.tool_call && <Badge variant="success">{isZh ? "工具调用" : "Tools"}</Badge>}
                    <Badge variant="outline">
                      {isZh ? "上下文" : "Ctx"} {Math.round(selectedCliCapabilities.context_window / 1024)}K
                    </Badge>
                  </div>
                )}
                <div className="connect-cli-preview relative overflow-hidden rounded-lg border">
                  <button
                    onClick={() => copyText(cliPreview, "cli")}
                    className="connect-code-copy-btn absolute top-3 right-3 rounded-xl p-3 cursor-pointer transition-colors"
                    title={isZh ? "复制配置预览" : "Copy preview"}
                  >
                    {copiedTarget === "cli" ? <Check className="h-4 w-4 text-green-600" /> : <Copy className="h-4 w-4" />}
                  </button>
                  <Suspense fallback={<pre className="overflow-x-auto text-xs text-slate-500">{cliPreview}</pre>}>
                    <CodeHighlighter
                      code={cliPreview}
                      language={cliPreviewLang}
                      dark={isDarkTheme}
                      padding="14px 16px"
                    />
                  </Suspense>
                </div>

                <div className="flex flex-wrap gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={!canSyncCli || syncCliMut.isPending}
                    onClick={() => {
                      setCliActionMessage(null);
                      syncCliMut.mutate();
                    }}
                  >
                    {syncCliMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Wrench className="h-3.5 w-3.5" />}
                    {syncCliMut.isPending
                      ? (isZh ? "同步中..." : "Syncing...")
                      : (isZh ? "同步配置" : "Sync Config")}
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={!IS_TAURI || restoreCliMut.isPending}
                    onClick={() => {
                      setCliActionMessage(null);
                      restoreCliMut.mutate();
                    }}
                  >
                    {restoreCliMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
                    {restoreCliMut.isPending
                      ? (isZh ? "恢复中..." : "Restoring...")
                      : (isZh ? "恢复原配置" : "Restore")}
                  </Button>
                </div>
                {cliRoutes.length === 0 && (
                  <p className="text-xs text-amber-600">
                    {isZh
                      ? "当前工具协议下没有可选路由，请先创建路由。"
                      : "No routes for this tool protocol. Create a route first."}
                  </p>
                )}
                {selectedCliRoute?.access_control && !selectedCliApiKey && (
                  <p className="text-xs text-amber-600">
                    {isZh
                      ? "当前路由开启了访问控制，请先选择 API Key 再同步。"
                      : "This route requires access control. Select an API key before syncing."}
                  </p>
                )}
                {cliActionMessage && (
                  <p className={`text-xs ${cliActionMessage.kind === "success" ? "text-green-600" : "text-red-600"}`}>
                    {cliActionMessage.text}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-xs text-amber-600">
                {isZh
                  ? "当前 CLI 未就绪，配置面板已隐藏。"
                  : "Selected CLI is not ready, configuration panel is hidden."}
              </p>
            )}
          </TabsContent>
        </Tabs>
      </div>
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
