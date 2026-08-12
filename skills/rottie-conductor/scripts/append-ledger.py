#!/usr/bin/env python3
"""Rottie 오케스트레이션 원장 append 헬퍼 (지휘자용).

프로토콜(docs/orchestration-file-protocol.md "추가 잠금과 손상 복구") 준수:
1. .append.lock을 읽기/쓰기로 열고 배타 advisory flock 획득 (5ms x 400회 재시도)
2. 잠금 보유 중 원장 재생해 다음 sequence 결정
3. 마지막 바이트가 \\n이 아니면 먼저 \\n 추가
4. JSON 한 줄 + \\n 추가 후 flush + fsync
5. 핸들 닫아 잠금 해제

사용: rottie-conductor-append.py <workspace> '<event_json>' ['<event_json>' ...]
각 event_json에는 sequence를 넣지 않는다 (이 스크립트가 부여). created_at은 없으면 현재 UTC.
"""
import fcntl
import json
import os
import sys
import time
from datetime import datetime, timezone

LOCK_RETRIES = 400
LOCK_INTERVAL_SEC = 0.005


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def acquire_lock(fd: int) -> None:
    for _ in range(LOCK_RETRIES):
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return
        except BlockingIOError:
            time.sleep(LOCK_INTERVAL_SEC)
    raise RuntimeError("append.lock 획득 실패: 2초 대기 후에도 잠금이 바쁨")


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: rottie-conductor-append.py <workspace> '<event_json>' [...]")
    workspace = sys.argv[1]
    events = [json.loads(a) for a in sys.argv[2:]]

    orch = os.path.join(workspace, ".rottie", "orchestration")
    os.makedirs(os.path.join(orch, "claims"), exist_ok=True)
    os.makedirs(os.path.join(orch, "delivery_claims"), exist_ok=True)
    lock_path = os.path.join(orch, ".append.lock")
    ledger_path = os.path.join(orch, "events.jsonl")

    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        acquire_lock(lock_fd)

        max_seq = 0
        if os.path.exists(ledger_path):
            with open(ledger_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        seq = json.loads(line).get("sequence", 0)
                    except json.JSONDecodeError:
                        continue  # 찢어진 줄은 건너뜀 (프로토콜 읽기 복구 규칙)
                    if isinstance(seq, int) and seq > max_seq:
                        max_seq = seq

        needs_nl = False
        if os.path.exists(ledger_path) and os.path.getsize(ledger_path) > 0:
            with open(ledger_path, "rb") as f:
                f.seek(-1, os.SEEK_END)
                needs_nl = f.read(1) != b"\n"

        with open(ledger_path, "a", encoding="utf-8") as f:
            if needs_nl:
                f.write("\n")
            for ev in events:
                max_seq += 1
                ev["sequence"] = max_seq
                ev.setdefault("created_at", utc_now())
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")
            f.flush()
            os.fsync(f.fileno())
        print(f"OK appended={len(events)} last_sequence={max_seq}")
    finally:
        os.close(lock_fd)


if __name__ == "__main__":
    main()
