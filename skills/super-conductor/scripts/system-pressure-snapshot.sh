#!/bin/bash
set -euo pipefail

PROJECT_FILTER="${1:-}"

python3 - "$PROJECT_FILTER" <<'PY'
import datetime
import json
import os
import pathlib
import subprocess
import sys

project_filter = sys.argv[1]

result = subprocess.run(
    ["ps", "-axo", "pid=,ppid=,%cpu=,%mem=,rss=,etime=,command="],
    check=True,
    capture_output=True,
    text=True,
)

def classify(command: str):
    lowered = command.lower()
    tokens = command.split()
    executable = pathlib.Path(tokens[0]).name.lower() if tokens else ""
    if "cargo test" in lowered:
        return "cargo_test"
    if "terminal_daemon_integration" in lowered:
        return "daemon_integration"
    if executable == "rottie-terminal-daemon":
        return "terminal_daemon"
    if "tauri dev" in lowered:
        return "tauri_dev"
    if "vitest" in lowered:
        return "vitest"
    if executable in {"vite", "vite-node"} or "/node_modules/.bin/vite" in lowered:
        return "vite"
    if executable.startswith("codex"):
        return "codex"
    if executable.startswith("claude"):
        return "claude"
    if executable == "gjc":
        return "gjc"
    if executable in {"orca", "orca-dev", "orca-ide"} or "/orca.app/" in lowered:
        return "orca"
    if "lsp" in executable or "lsp-daemon" in lowered:
        return "lsp"
    if "mcp" in executable or "mcp-server" in lowered:
        return "mcp"
    return None

raw_processes = []
for line in result.stdout.splitlines():
    parts = line.strip().split(None, 6)
    if len(parts) != 7:
        continue
    pid, ppid, cpu, mem, rss, elapsed, command = parts
    raw_processes.append((int(pid), int(ppid), cpu, mem, rss, elapsed, command))

parents = {pid: ppid for pid, ppid, *_ in raw_processes}
excluded = set()
current = os.getpid()
while current > 1 and current not in excluded:
    excluded.add(current)
    current = parents.get(current, 0)

processes = []
for pid, ppid, cpu, mem, rss, elapsed, command in raw_processes:
    process_class = classify(command)
    if process_class is None or pid in excluded:
        continue
    if project_filter and project_filter not in command:
        continue
    executable = pathlib.Path(command.split()[0]).name if command.split() else "unknown"
    processes.append(
        {
            "pid": pid,
            "ppid": ppid,
            "cpu_percent": float(cpu),
            "memory_percent": float(mem),
            "rss_mb": round(int(rss) / 1024, 1),
            "elapsed": elapsed,
            "class": process_class,
            "executable": executable,
        }
    )

groups = {}
for process in processes:
    group = groups.setdefault(process["class"], {"count": 0, "rss_mb": 0.0, "cpu_percent": 0.0})
    group["count"] += 1
    group["rss_mb"] = round(group["rss_mb"] + process["rss_mb"], 1)
    group["cpu_percent"] = round(group["cpu_percent"] + process["cpu_percent"], 1)

payload = {
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "project_filter": project_filter or None,
    "logical_cpus": os.cpu_count(),
    "load_average": [round(value, 2) for value in os.getloadavg()],
    "matched_process_count": len(processes),
    "matched_rss_mb": round(sum(process["rss_mb"] for process in processes), 1),
    "groups": groups,
    "top_processes": sorted(processes, key=lambda item: (item["rss_mb"], item["cpu_percent"]), reverse=True)[:30],
}
print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
