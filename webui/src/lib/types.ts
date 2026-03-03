export interface Provider {
  id: string;
  name: string;
  protocol: string;
  base_url: string;
  is_active: boolean;
  priority: number;
  created_at: string;
  updated_at: string;
}

export interface Route {
  id: string;
  name: string;
  match_pattern: string;
  target_provider: string;
  target_model: string;
  fallback_provider?: string;
  fallback_model?: string;
  is_active: boolean;
  priority: number;
  created_at: string;
}

export interface RequestLog {
  id: string;
  created_at: string;
  ingress_protocol?: string;
  egress_protocol?: string;
  request_model?: string;
  actual_model?: string;
  provider_name?: string;
  status_code?: number;
  duration_ms?: number;
  input_tokens: number;
  output_tokens: number;
  is_stream: boolean;
  is_tool_call: boolean;
  error_message?: string;
}

export interface GatewayStatus {
  status: string;
  proxy_port: number;
}

export interface StatsOverview {
  total_requests: number;
  total_tokens: number;
  avg_latency_ms: number;
  error_rate: number;
}

export interface CreateProvider {
  name: string;
  protocol: string;
  base_url: string;
  api_key: string;
}

export interface CreateRoute {
  name: string;
  match_pattern: string;
  target_provider: string;
  target_model: string;
  fallback_provider?: string;
  fallback_model?: string;
}
