# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic>=2.12,<3", "typer>=0.16,<1"]
# ///
# ─── How to run ───
# curl -s http://127.0.0.1:10100/api/provider-quotas | uv run select_routing_pair.py --quota-file - --task-size heavy --unavailable-provider zai

from __future__ import annotations

import sys
import time
import urllib.error
import urllib.request
from collections.abc import Mapping
from enum import StrEnum
from hashlib import sha256
from pathlib import Path
from types import MappingProxyType
from typing import Annotated, ClassVar, Final

import typer
from pydantic import BaseModel, ConfigDict, Field


class Role(StrEnum):
    DEVELOPER = "developer"
    REVIEWER = "reviewer"


class TaskSize(StrEnum):
    LIGHT = "light"
    HEAVY = "heavy"


class ModelConfig(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, populate_by_name=True)
    id: str
    role: Role
    effort: str
    quality: float
    command: str
    experimental: bool = False
    experiment_share_percent: int = Field(
        default=100, alias="experimentSharePercent", ge=0, le=100
    )
    reviewer_family_allowlist: tuple[str, ...] = Field(
        default=(), alias="reviewerFamilyAllowlist"
    )


class ProviderConfig(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, populate_by_name=True)
    id: str
    family: str
    quota_key: str | None = Field(alias="quotaKey")
    enabled: bool
    weekly_reserve: float = Field(alias="weeklyReservePercent")
    models: tuple[ModelConfig, ...]


class RoutingConfig(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    providers: tuple[ProviderConfig, ...]


class QuotaMetrics(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, populate_by_name=True)
    five_hour_used: float | None = Field(default=None, alias="fiveHourPercent")
    five_hour_reset_ms: int | None = Field(default=None, alias="fiveHourResetAt")
    weekly_used: float | None = Field(default=None, alias="weeklyPercent")
    weekly_reset_ms: int | None = Field(default=None, alias="weeklyResetAt")


class QuotaReport(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, populate_by_name=True)
    provider: str
    updated_at: int | None = Field(default=None, alias="updatedAt")
    quota: QuotaMetrics


class QuotaResponse(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, populate_by_name=True)
    generated_at: int = Field(alias="generatedAt")
    reports: tuple[QuotaReport, ...]


class SelectionRequest(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    config_path: Path
    quota_json: str
    task_size: TaskSize
    unavailable_providers: frozenset[str]
    now_ms: int
    experiment_key: str | None = None


class RoutedModel(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    provider: str
    family: str
    model: str
    effort: str
    command: str


class RankedPair(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    developer: RoutedModel
    reviewer: RoutedModel
    score: float
    last_resort: bool
    same_family: bool
    reasons: tuple[str, ...]


class RoutingDecision(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    developer: RoutedModel
    reviewer: RoutedModel
    score: float
    last_resort: bool
    same_family: bool
    reasons: tuple[str, ...]
    ranked_pairs: tuple[RankedPair, ...]


class ProviderHealth(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    available: bool
    last_resort: bool
    score: float
    reasons: tuple[str, ...]


class RoutingError(RuntimeError):
    pass


WEEK_MS: Final = 604_800_000
FIVE_HOURS_MS: Final = 18_000_000
DAY_MS: Final = 86_400_000
HOUR_MS: Final = 3_600_000
WEEKLY_RESET_URGENCY_MAX_SCORE: Final = 15.0
DEFAULT_CONFIG: Final = Path(__file__).parents[1] / "references" / "routing-providers.json"
DEFAULT_ROTTIE_QUOTA: Final = Path.home() / ".cache" / "rottie" / "routing-usage.json"
ROTTIE_FRESHNESS_MS: Final = 20 * 60 * 1000
OPENCODEX_QUOTA_URL: Final = "http://127.0.0.1:10100/api/provider-quotas"
TASK_COSTS: Final[Mapping[TaskSize, tuple[float, float]]] = MappingProxyType(
    {TaskSize.LIGHT: (2.0, 1.0), TaskSize.HEAVY: (5.0, 3.0)}
)


def release_factor(reset_ms: int | None, now_ms: int, release_window_ms: int) -> float:
    if reset_ms is None:
        return 1.0
    return max(0.0, min(1.0, (reset_ms - now_ms) / release_window_ms))


def quota_health(
    provider: ProviderConfig,
    cost: float,
    quota: QuotaMetrics | None,
    now_ms: int,
) -> ProviderHealth:
    if quota is None:
        return ProviderHealth(available=True, last_resort=False, score=5, reasons=("quota_unknown",))
    score = 0.0
    last_resort = False
    reasons: list[str] = []
    weekly_reserve = provider.weekly_reserve * release_factor(
        quota.weekly_reset_ms, now_ms, DAY_MS
    )
    five_hour_headroom = 1 + 0.5 * release_factor(
        quota.five_hour_reset_ms, now_ms, HOUR_MS
    )
    windows = (
        ("weekly", quota.weekly_used, quota.weekly_reset_ms, WEEK_MS, weekly_reserve),
        (
            "five_hour",
            quota.five_hour_used,
            quota.five_hour_reset_ms,
            FIVE_HOURS_MS,
            cost * (five_hour_headroom - 1),
        ),
    )
    reasons.extend(
        (
            f"weekly_reserve={weekly_reserve:.2f}",
            f"five_hour_headroom={five_hour_headroom:.2f}",
        )
    )
    for name, used, reset_ms, duration_ms, reserve in windows:
        if used is None:
            continue
        remaining_after = 100 - used - cost
        if remaining_after < 0:
            return ProviderHealth(available=False, last_resort=True, score=-1000, reasons=(f"{name}_exhausted",))
        score += remaining_after * 0.15
        if remaining_after < reserve:
            last_resort = True
            score -= 45
            reasons.append(f"{name}_reserve_breach")
        if reset_ms is not None:
            elapsed = max(1.0, min(100.0, (1 - (reset_ms - now_ms) / duration_ms) * 100))
            pace = used / elapsed
            if pace > 1:
                score -= (pace - 1) * 20
                reasons.append(f"{name}_pace={pace:.2f}")
    if quota.weekly_used is not None and quota.weekly_reset_ms is not None:
        time_until_weekly_reset = quota.weekly_reset_ms - now_ms
        if 0 <= time_until_weekly_reset < DAY_MS:
            weekly_reset_urgency = WEEKLY_RESET_URGENCY_MAX_SCORE * (
                1 - time_until_weekly_reset / DAY_MS
            )
            score += weekly_reset_urgency
            reasons.append(f"weekly_reset_urgency={weekly_reset_urgency:.2f}")
    return ProviderHealth(
        available=True,
        last_resort=last_resort,
        score=score,
        reasons=tuple(reasons) or ("quota_healthy",),
    )


def routed_model(provider: ProviderConfig, model: ModelConfig) -> RoutedModel:
    return RoutedModel(
        provider=provider.id,
        family=provider.family,
        model=model.id,
        effort=model.effort,
        command=model.command,
    )


def experiment_bucket(model: ModelConfig, experiment_key: str) -> int:
    digest = sha256(f"{model.id}\0{experiment_key}".encode()).digest()
    return int.from_bytes(digest[:8], "big") % 100


def experiment_reasons(
    model: ModelConfig, experiment_key: str | None
) -> tuple[str, ...] | None:
    if not model.experimental:
        return ()
    if experiment_key is None:
        return None
    bucket = experiment_bucket(model, experiment_key)
    if bucket >= model.experiment_share_percent:
        return None
    return (
        f"experiment_bucket={bucket}",
        f"experiment_share={model.experiment_share_percent}",
    )


def merge_quota_sources(
    fallback: QuotaResponse | None,
    rottie: QuotaResponse | None,
    now_ms: int,
) -> QuotaResponse:
    reports = {report.provider: report for report in fallback.reports} if fallback else {}
    if rottie is not None:
        for report in rottie.reports:
            observed_at = report.updated_at or rottie.generated_at
            age_ms = now_ms - observed_at
            if 0 <= age_ms <= ROTTIE_FRESHNESS_MS:
                reports[report.provider] = report
    if not reports:
        raise RoutingError("No quota source is available")
    return QuotaResponse(
        generatedAt=max(
            fallback.generated_at if fallback else 0,
            rottie.generated_at if rottie else 0,
        ),
        reports=tuple(reports.values()),
    )


def read_quota_file(path: str | Path | None) -> QuotaResponse | None:
    if path is None:
        return None
    if path == "-":
        raw = sys.stdin.read()
    else:
        quota_path = Path(path).expanduser()
        if not quota_path.exists():
            return None
        raw = quota_path.read_text()
    if not raw.strip():
        return None
    return QuotaResponse.model_validate_json(raw)


def read_opencodex_fallback() -> QuotaResponse | None:
    try:
        with urllib.request.urlopen(OPENCODEX_QUOTA_URL, timeout=3) as response:
            return QuotaResponse.model_validate_json(response.read())
    except (OSError, urllib.error.URLError, ValueError):
        return None


def select_pair(request: SelectionRequest) -> RoutingDecision:
    config = RoutingConfig.model_validate_json(request.config_path.read_text())
    quota_response = QuotaResponse.model_validate_json(request.quota_json)
    quotas = {report.provider: report.quota for report in quota_response.reports}
    dev_cost, review_cost = TASK_COSTS[request.task_size]
    pairs: list[RankedPair] = []
    providers = tuple(provider for provider in config.providers if provider.enabled)
    for dev_provider in providers:
        if dev_provider.id in request.unavailable_providers:
            continue
        for dev_model in (model for model in dev_provider.models if model.role is Role.DEVELOPER):
            dev_experiment_reasons = experiment_reasons(dev_model, request.experiment_key)
            if dev_experiment_reasons is None:
                continue
            for review_provider in providers:
                if review_provider.id in request.unavailable_providers:
                    continue
                if (
                    dev_model.reviewer_family_allowlist
                    and review_provider.family not in dev_model.reviewer_family_allowlist
                ):
                    continue
                for review_model in (model for model in review_provider.models if model.role is Role.REVIEWER):
                    if dev_model.id == review_model.id:
                        continue
                    costs = {dev_provider.id: dev_cost, review_provider.id: review_cost}
                    if dev_provider.id == review_provider.id:
                        costs[dev_provider.id] = dev_cost + review_cost
                    dev_health = quota_health(
                        dev_provider,
                        costs[dev_provider.id],
                        quotas.get(dev_provider.quota_key or ""),
                        request.now_ms,
                    )
                    review_health = quota_health(
                        review_provider,
                        costs[review_provider.id],
                        quotas.get(review_provider.quota_key or ""),
                        request.now_ms,
                    )
                    if not dev_health.available or not review_health.available:
                        continue
                    same_family = dev_provider.family == review_provider.family
                    diversity_score = -35 if same_family else 20
                    score = (
                        dev_model.quality
                        + review_model.quality
                        + dev_health.score
                        + review_health.score
                        + diversity_score
                    )
                    pairs.append(
                        RankedPair(
                            developer=routed_model(dev_provider, dev_model),
                            reviewer=routed_model(review_provider, review_model),
                            score=round(score, 2),
                            last_resort=dev_health.last_resort or review_health.last_resort,
                            same_family=same_family,
                            reasons=(
                                dev_experiment_reasons
                                + dev_health.reasons
                                + review_health.reasons
                            ),
                        )
                    )
    if not pairs:
        raise RoutingError("No runnable developer/reviewer pair remains")
    ranked = tuple(sorted(pairs, key=lambda pair: (pair.last_resort, -pair.score)))
    selected = ranked[0]
    return RoutingDecision(
        developer=selected.developer,
        reviewer=selected.reviewer,
        score=selected.score,
        last_resort=selected.last_resort,
        same_family=selected.same_family,
        reasons=selected.reasons,
        ranked_pairs=ranked,
    )


app = typer.Typer(add_completion=False)


@app.command()
def main(
    quota_file: Annotated[str | None, typer.Option()] = None,
    rottie_quota_file: Annotated[Path, typer.Option()] = DEFAULT_ROTTIE_QUOTA,
    task_size: Annotated[TaskSize, typer.Option()] = TaskSize.HEAVY,
    config: Annotated[Path, typer.Option()] = DEFAULT_CONFIG,
    unavailable_provider: Annotated[list[str] | None, typer.Option()] = None,
    experiment_key: Annotated[str | None, typer.Option()] = None,
) -> None:
    now_ms = int(time.time() * 1000)
    rottie = read_quota_file(rottie_quota_file)
    fallback = read_quota_file(quota_file) if quota_file is not None else read_opencodex_fallback()
    quota_json = merge_quota_sources(fallback, rottie, now_ms).model_dump_json(by_alias=True)
    decision = select_pair(
        SelectionRequest(
            config_path=config,
            quota_json=quota_json,
            task_size=task_size,
            unavailable_providers=frozenset(unavailable_provider or ()),
            now_ms=now_ms,
            experiment_key=experiment_key,
        )
    )
    typer.echo(decision.model_dump_json(by_alias=True, indent=2))


if __name__ == "__main__":
    app()
