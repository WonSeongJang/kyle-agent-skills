from __future__ import annotations

from datetime import datetime
from pathlib import Path

from .config import DailyConfig


DEFAULT_TEMPLATE = """### 요청 / 목적

{purpose}

### 한 일

{done}

### 판단 / 메모

{notes}

### 다음 할 일

{next_steps}
"""


class DailyLogger:
    def __init__(self, config: DailyConfig):
        self.config = config

    def write(
        self,
        tool: str,
        purpose: str,
        done: str,
        notes: str = "-",
        next_steps: str = "-",
    ) -> Path | None:
        if not self.config.enabled:
            return None

        now = datetime.now()
        date_str = now.strftime("%Y-%m-%d")
        time_str = now.strftime("%H:%M")

        day_dir = self.config.dir / date_str
        day_dir.mkdir(parents=True, exist_ok=True)
        log_file = day_dir / f"{tool}.md"

        if not log_file.exists():
            log_file.write_text(f"# {date_str} {tool} 작업 로그\n", encoding="utf-8")

        entry = f"\n## {time_str} 작업\n\n" + DEFAULT_TEMPLATE.format(
            purpose=purpose,
            done=done,
            notes=notes,
            next_steps=next_steps,
        )
        with open(log_file, "a", encoding="utf-8") as handle:
            handle.write(entry)

        return log_file
