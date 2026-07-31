#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic>=2.12,<3", "typer>=0.16,<1"]
# ///
# ─── How to run ───
# 1. Install uv (if not installed):
#      curl -LsSf https://astral.sh/uv/install.sh | sh
# 2. Run directly (no venv, no pip install needed):
#      uv run routing_shadow.py --config <path> --task-class <class> < decision.json
# 3. Or make executable and run:
#      chmod +x routing_shadow.py && ./routing_shadow.py --config <path> --task-class <class> < decision.json
# ─────────────────

from __future__ import annotations

import sys
from enum import StrEnum
from pathlib import Path
from typing import Annotated, ClassVar, TypeAlias

import typer
from pydantic import BaseModel, ConfigDict, Field, JsonValue


class TaskClass(StrEnum):
    TARGETED_IMPLEMENTATION = "targeted_implementation"
    FRONTEND = "frontend"
    ARCHITECTURE = "architecture"
    RESEARCH = "research"
    SECURITY = "security"
    CONCURRENCY = "concurrency"
    BUGFIX = "bugfix"
    DOCS_CONFIG = "docs_config"
    QA = "qa"
    OTHER = "other"


class Role(StrEnum):
    DEVELOPER = "developer"
    REVIEWER = "reviewer"


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
    ranked_pairs: tuple[RankedPair, ...] = Field(min_length=1)
    exploration: JsonValue | None = None


class ModelConfig(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(
        frozen=True,
        populate_by_name=True,
        extra="ignore",
    )
    id: str
    role: Role
    effort: str
    harness: str
    task_class_prior: dict[TaskClass, float] = Field(alias="taskClassPrior")


class ProviderConfig(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")
    id: str
    models: tuple[ModelConfig, ...]


class RoutingConfig(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, extra="ignore")
    providers: tuple[ProviderConfig, ...]


class ShadowModel(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    provider: str
    model: str
    effort: str
    harness: str
    task_class_prior: float


class ShadowCandidate(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    developer: ShadowModel
    reviewer: ShadowModel
    actual_score: float
    task_class_score: float
    shadow_score: float
    last_resort: bool
    same_family: bool


class ShadowDecision(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)
    task_class: TaskClass
    selected: ShadowCandidate
    ranked_pairs: tuple[ShadowCandidate, ...]


class RoutingLedgerPayload(RoutingDecision):
    shadow: ShadowDecision


ModelKey: TypeAlias = tuple[str, str, Role, str]


def model_key(model: RoutedModel, role: Role) -> ModelKey:
    return (model.provider, model.model, role, model.effort)


def shadow_model(
    routed: RoutedModel,
    registered: ModelConfig,
    task_class: TaskClass,
) -> ShadowModel:
    return ShadowModel(
        provider=routed.provider,
        model=routed.model,
        effort=routed.effort,
        harness=registered.harness,
        task_class_prior=registered.task_class_prior.get(task_class, 0.0),
    )


def build_shadow_payload(
    decision: RoutingDecision,
    config: RoutingConfig,
    task_class: TaskClass,
) -> RoutingLedgerPayload:
    registered = {
        (provider.id, model.id, model.role, model.effort): model
        for provider in config.providers
        for model in provider.models
    }
    candidates = tuple(
        ShadowCandidate(
            developer=shadow_model(
                pair.developer,
                registered[model_key(pair.developer, Role.DEVELOPER)],
                task_class,
            ),
            reviewer=shadow_model(
                pair.reviewer,
                registered[model_key(pair.reviewer, Role.REVIEWER)],
                task_class,
            ),
            actual_score=pair.score,
            task_class_score=(
                registered[model_key(pair.developer, Role.DEVELOPER)].task_class_prior.get(task_class, 0.0)
                + registered[model_key(pair.reviewer, Role.REVIEWER)].task_class_prior.get(task_class, 0.0)
            ),
            shadow_score=round(
                pair.score
                + registered[model_key(pair.developer, Role.DEVELOPER)].task_class_prior.get(task_class, 0.0)
                + registered[model_key(pair.reviewer, Role.REVIEWER)].task_class_prior.get(task_class, 0.0),
                2,
            ),
            last_resort=pair.last_resort,
            same_family=pair.same_family,
        )
        for pair in decision.ranked_pairs
    )
    ranked = tuple(sorted(candidates, key=lambda pair: (pair.last_resort, -pair.shadow_score)))[:10]
    return RoutingLedgerPayload(
        developer=decision.developer,
        reviewer=decision.reviewer,
        score=decision.score,
        last_resort=decision.last_resort,
        same_family=decision.same_family,
        reasons=decision.reasons,
        ranked_pairs=decision.ranked_pairs,
        exploration=decision.exploration,
        shadow=ShadowDecision(
            task_class=task_class,
            selected=ranked[0],
            ranked_pairs=ranked,
        ),
    )


def main(
    config: Annotated[Path, typer.Option(exists=True, dir_okay=False)],
    task_class: Annotated[TaskClass, typer.Option()],
) -> None:
    decision = RoutingDecision.model_validate_json(sys.stdin.read())
    routing_config = RoutingConfig.model_validate_json(config.read_text())
    payload = build_shadow_payload(decision, routing_config, task_class)
    typer.echo(payload.model_dump_json(by_alias=True))


if __name__ == "__main__":
    typer.run(main)
