#!/bin/bash
set -u
[ $# -ge 1 ] || { echo "usage: watch-terminals.sh <terminal_handle> [terminal_handle...] | --list FILE"; exit 2; }
python3 - "$@" <<'PY'
import json, os, re, subprocess, sys, time
args = sys.argv[1:]
list_path = None
if args[:1] == ["--list"]:
    if len(args) != 2 or not args[1]:
        print("usage: watch-terminals.sh --list FILE", file=sys.stderr)
        raise SystemExit(2)
    list_path = args[1]
    handles = []
else:
    handles = args
interval = max(1, int(os.environ.get("WATCH_INTERVAL_SEC", "90")))
deadline = time.time() + float(os.environ.get("WATCH_DEADLINE_MIN", "60")) * 60
signatures = re.compile(r"429 Too Many Requests|exceeded retry limit|stream error|stream disconnected|No API key|rate limit", re.I)
previous = {handle: set() for handle in handles}
failures = {handle: 0 for handle in handles}
baseline = {handle: False for handle in handles}
max_failures = max(1, int(os.environ.get("WATCH_READ_FAILURES", "3")))

def read_handles():
    if list_path is None:
        return handles
    try:
        with open(list_path, encoding="utf-8") as handle_file:
            return [line.strip() for line in handle_file if line.strip() and not line.lstrip().startswith("#")]
    except OSError:
        return []

def read_tail(handle):
    try:
        proc = subprocess.run(["orca", "terminal", "read", "--terminal", handle, "--limit", "6", "--json"], capture_output=True, text=True, timeout=30)
    except (subprocess.TimeoutExpired, OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        terminal = (json.loads(proc.stdout).get("result") or {}).get("terminal")
        if not isinstance(terminal, dict) or "tail" not in terminal:
            return None
        tail = terminal["tail"]
        return "\n".join(str(x) for x in tail[-6:]) if isinstance(tail, list) else "\n".join(str(tail).splitlines()[-6:])
    except (json.JSONDecodeError, TypeError, AttributeError):
        return None

while time.time() < deadline:
    active_handles = set(read_handles())
    if list_path is not None:
        for handle in set(previous) - active_handles:
            previous.pop(handle, None)
            failures.pop(handle, None)
            baseline.pop(handle, None)
        for handle in active_handles - set(previous):
            previous[handle] = set()
            failures[handle] = 0
            baseline[handle] = False
    for handle in active_handles:
        tail = read_tail(handle)
        if tail is None:
            failures[handle] += 1
            if failures[handle] >= max_failures:
                print(f"GONE {handle}", flush=True); raise SystemExit(1)
            continue
        failures[handle] = 0
        current = set()
        for match in signatures.finditer(tail):
            line = tail[:match.end()].splitlines()[-1].strip()
            current.add(f"{match.group(0).lower()}|{line}")
        fresh = current - previous[handle]
        if baseline[handle] and fresh:
            if handle not in set(read_handles()):
                continue
            print(f"ERROR {handle} {sorted(fresh)[0].split('|', 1)[1]}", flush=True); raise SystemExit(1)
        previous[handle] = current
        baseline[handle] = True
    time.sleep(interval)
print("DEADLINE_REACHED", flush=True); raise SystemExit(1)
PY
