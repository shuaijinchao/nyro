import { ScrollText } from "lucide-react";

export default function LogsPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Request Logs</h1>
        <p className="mt-1 text-sm text-slate-500">
          Real-time request log viewer
        </p>
      </div>
      <div className="glass rounded-2xl p-12 text-center">
        <ScrollText className="mx-auto h-10 w-10 text-slate-400" />
        <p className="mt-3 text-sm text-slate-500">
          Logs will appear here once the proxy starts handling requests
        </p>
      </div>
    </div>
  );
}
