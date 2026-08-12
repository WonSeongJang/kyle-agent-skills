from __future__ import annotations

import json
import os
import secrets
from pathlib import Path


def _write_private_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.parent.chmod(0o700)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}-{secrets.token_hex(4)}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        temporary.unlink(missing_ok=True)


def write_private_text(path: Path, content: str) -> None:
    _write_private_text(path, content)


def write_private_json(path: Path, payload: dict[str, object]) -> None:
    encoded = f"{json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)}\n"
    _write_private_text(path, encoded)
