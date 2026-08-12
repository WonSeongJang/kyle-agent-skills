from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Final

MAX_DOCUMENT_CHARS: Final = 12_000
MAX_PERFORMANCE_CHARS: Final = 2_000

_SECRET_ASSIGNMENT: Final = re.compile(
    r"(?im)\b(token|password|passwd|secret|api[_-]?key|access[_-]?key|authorization)\b"
    r"(\s*[:=]\s*)(?:['\"]?)[^\s'\"`]+"
)
_BEARER: Final = re.compile(r"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+")
_PRIVATE_KEY: Final = re.compile(
    r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
    re.DOTALL,
)
_AWS_KEY: Final = re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")


def redact_text(text: str) -> str:
    redacted = _PRIVATE_KEY.sub("[REDACTED PRIVATE KEY]", text)
    redacted = _SECRET_ASSIGNMENT.sub(lambda match: f"{match.group(1)}{match.group(2)}[REDACTED]", redacted)
    redacted = _BEARER.sub(lambda match: f"{match.group(1)} [REDACTED]", redacted)
    return _AWS_KEY.sub("[REDACTED]", redacted)


def bounded_text(text: str, limit: int = MAX_DOCUMENT_CHARS) -> tuple[str, bool]:
    redacted = redact_text(text)
    if len(redacted) <= limit:
        return redacted, False
    return f"{redacted[:limit]}\n[TRUNCATED]\n", True


def file_digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def is_sensitive_path(path: Path) -> bool:
    lowered_parts = tuple(part.lower() for part in path.parts)
    if any(part in {".git", "node_modules", "secrets", "private"} for part in lowered_parts):
        return True
    name = path.name.lower()
    return name == ".env" or name.startswith(".env.")
