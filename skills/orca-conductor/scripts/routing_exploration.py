#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic>=2.12,<3", "typer>=0.16,<1"]
# ///
# pyright: reportUnnecessaryComparison=false
# ─── How to run ───
# 1. Install uv (if not installed):
#      curl -LsSf https://astral.sh/uv/install.sh | sh
# 2. Run directly (no venv, no pip install needed):
#      uv run routing_exploration.py --config <path> --task-class <class> --task-size <size> --experiment-key <key> < decision.json
# 3. Or make executable and run:
#      chmod +x routing_exploration.py && ./routing_exploration.py --config <path> --task-class <class> --task-size <size> --experiment-key <key> < decision.json
# ─────────────────

from __future__ import annotations

import sys
from dataclasses import dataclass
from enum import StrEnum
from hashlib import sha256
from pathlib import Path
from typing import Annotated, ClassVar, Final, TypeAlias, assert_never

import typer
from pydantic import BaseModel, ConfigDict, Field

MAX_SCORE_GAP: Final = 15.0
SHORTLIST_SIZE: Final = 3


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


class TaskSize(StrEnum):
    LIGHT = "LIGHT"
    HEAVY = "HEAVY"


class RiskFlag(StrEnum):
    SECURITY = "security"
    CONCURRENCY = "concurrency"
    MIGRATION = "migration"
    EXTERNAL_API = "external_api"
    MULTI_REPO = "multi_repo"
    USER_VISIBLE = "user_visible"
    PRODUCTION_DATA = "production_data"
    UNKNOWN_DESIGN = "unknown_design"


class Role(StrEnum):
    DEVELOPER = "developer"
    REVIEWER = "reviewer"


class ExplorationReason(StrEnum):
    SELECTED = "selected"
    SHARE_DISABLED = "share_disabled"
    RISK_ASSESSMENT_REQUIRED = "risk_assessment_required"
    RISK_FLAGGED = "risk_flagged"
    UNSAFE_TASK_CONTEXT = "unsafe_task_context"
    OUTSIDE_SHARE = "outside_share"
    NO_SAFE_ALTERNATIVE = "no_safe_alternative"


class StrictModel(BaseModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True, strict=True, extra="forbid")


class RoutedModel(StrictModel):
    provider: str
    family: str
    model: str
    effort: str
    command: str


class RankedPair(StrictModel):
    developer: RoutedModel
    reviewer: RoutedModel
    score: float
    last_resort: bool
    same_family: bool
    reasons: tuple[str, ...]


class RoutingDecision(RankedPair):
    ranked_pairs: tuple[RankedPair, ...] = Field(min_length=1)


class ModelRegistration(StrictModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(populate_by_name=True, extra="ignore")
    id: str
    role: Role
    effort: str
    harness: str
    task_class_prior: dict[TaskClass, float] = Field(alias="taskClassPrior")


class ProviderRegistration(StrictModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore")
    id: str
    models: tuple[ModelRegistration, ...]


class RoutingConfig(StrictModel):
    model_config: ClassVar[ConfigDict] = ConfigDict(extra="ignore")
    providers: tuple[ProviderRegistration, ...]


class ExplorationContext(StrictModel):
    task_class: TaskClass
    task_size: TaskSize
    experiment_key: str = Field(min_length=1)
    share_percent: int = Field(ge=0, le=10)
    risk_flags: tuple[RiskFlag, ...]
    risk_assessment_complete: bool = False


class ExplorationRequest(StrictModel):
    decision: RoutingDecision
    config: RoutingConfig
    context: ExplorationContext


class Assignment(StrictModel):
    provider: str
    model: str
    effort: str
    harness: str


class PairAssignment(StrictModel):
    developer: Assignment
    reviewer: Assignment


class ExplorationTrace(StrictModel):
    selected: bool
    eligible: bool
    reason: ExplorationReason
    bucket: int = Field(ge=0, le=99)
    share_percent: int = Field(ge=0, le=10)
    task_class: TaskClass
    task_size: TaskSize
    risk_flags: tuple[RiskFlag, ...]
    risk_assessment_complete: bool
    base: PairAssignment
    chosen: PairAssignment


class ExploredDecision(RoutingDecision):
    exploration: ExplorationTrace


ModelKey: TypeAlias = tuple[str, str, Role, str]


@dataclass(frozen=True, slots=True)
class ExplorationOutcome:
    reason: ExplorationReason
    eligible: bool
    bucket: int
    chosen: RankedPair | None = None


def exploration_bucket(experiment_key: str, task_class: TaskClass) -> int:
    digest = sha256(f"{experiment_key}\0{task_class.value}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % 100


def exploration_slot(experiment_key: str, task_class: TaskClass, candidate_count: int) -> int:
    digest = sha256(f"{experiment_key}\0{task_class.value}\0rotation".encode()).digest()
    return int.from_bytes(digest[4:8], "big") % candidate_count


def context_is_safe(context: ExplorationContext) -> bool:
    match context.task_class:
        case TaskClass.DOCS_CONFIG | TaskClass.RESEARCH | TaskClass.QA:
            return True
        case TaskClass.TARGETED_IMPLEMENTATION | TaskClass.FRONTEND | TaskClass.BUGFIX:
            return context.task_size is TaskSize.LIGHT
        case TaskClass.ARCHITECTURE | TaskClass.SECURITY | TaskClass.CONCURRENCY | TaskClass.OTHER:
            return False
        case _ as unreachable:
            assert_never(unreachable)


def apply_exploration(request: ExplorationRequest) -> ExploredDecision:
    registry = {
        (provider.id, model.id, model.role, model.effort): model
        for provider in request.config.providers
        for model in provider.models
    }
    context = request.context
    bucket = exploration_bucket(context.experiment_key, context.task_class)
    if context.share_percent == 0:
        outcome = ExplorationOutcome(ExplorationReason.SHARE_DISABLED, False, bucket)
    elif not context.risk_assessment_complete:
        outcome = ExplorationOutcome(ExplorationReason.RISK_ASSESSMENT_REQUIRED, False, bucket)
    elif context.risk_flags:
        outcome = ExplorationOutcome(ExplorationReason.RISK_FLAGGED, False, bucket)
    elif not context_is_safe(context):
        outcome = ExplorationOutcome(ExplorationReason.UNSAFE_TASK_CONTEXT, False, bucket)
    elif bucket >= context.share_percent:
        outcome = ExplorationOutcome(ExplorationReason.OUTSIDE_SHARE, True, bucket)
    else:
        base = request.decision
        alternatives = tuple(
            sorted(
                (
                    pair
                    for pair in base.ranked_pairs
                    if not pair.last_resort
                    and pair.score >= base.score - MAX_SCORE_GAP
                    and (pair.developer != base.developer or pair.reviewer != base.reviewer)
                ),
                key=lambda pair: (
                    -pair.score
                    - registry[(pair.developer.provider, pair.developer.model, Role.DEVELOPER, pair.developer.effort)]
                    .task_class_prior.get(context.task_class, 0.0)
                    - registry[(pair.reviewer.provider, pair.reviewer.model, Role.REVIEWER, pair.reviewer.effort)]
                    .task_class_prior.get(context.task_class, 0.0),
                    -pair.score,
                    pair.developer.provider,
                    pair.reviewer.provider,
                ),
            )[:SHORTLIST_SIZE]
        )
        if alternatives:
            chosen = alternatives[exploration_slot(context.experiment_key, context.task_class, len(alternatives))]
            outcome = ExplorationOutcome(ExplorationReason.SELECTED, True, bucket, chosen)
        else:
            outcome = ExplorationOutcome(ExplorationReason.NO_SAFE_ALTERNATIVE, True, bucket)
    return build_result(request, registry, outcome)


def build_result(
    request: ExplorationRequest,
    registry: dict[ModelKey, ModelRegistration],
    outcome: ExplorationOutcome,
) -> ExploredDecision:
    selected = outcome.chosen or request.decision

    def assignment(model: RoutedModel, role: Role) -> Assignment:
        registered = registry[(model.provider, model.model, role, model.effort)]
        return Assignment(provider=model.provider, model=model.model, effort=model.effort, harness=registered.harness)

    def pair_assignment(pair: RankedPair) -> PairAssignment:
        return PairAssignment(
            developer=assignment(pair.developer, Role.DEVELOPER),
            reviewer=assignment(pair.reviewer, Role.REVIEWER),
        )

    reasons = selected.reasons
    if outcome.chosen is not None:
        reasons += (
            f"exploration_share={request.context.share_percent}",
            f"exploration_bucket={outcome.bucket}",
            f"task_class={request.context.task_class.value}",
        )
    return ExploredDecision(
        developer=selected.developer,
        reviewer=selected.reviewer,
        score=selected.score,
        last_resort=selected.last_resort,
        same_family=selected.same_family,
        reasons=reasons,
        ranked_pairs=request.decision.ranked_pairs,
        exploration=ExplorationTrace(
            selected=outcome.chosen is not None,
            eligible=outcome.eligible,
            reason=outcome.reason,
            bucket=outcome.bucket,
            share_percent=request.context.share_percent,
            task_class=request.context.task_class,
            task_size=request.context.task_size,
            risk_flags=request.context.risk_flags,
            risk_assessment_complete=request.context.risk_assessment_complete,
            base=pair_assignment(request.decision),
            chosen=pair_assignment(selected),
        ),
    )


def main(
    config: Annotated[Path, typer.Option(exists=True, dir_okay=False)],
    task_class: Annotated[TaskClass, typer.Option()],
    task_size: Annotated[TaskSize, typer.Option()],
    experiment_key: Annotated[str, typer.Option(min=1)],
    share_percent: Annotated[int, typer.Option(min=0, max=10)] = 0,
    risk_flag: Annotated[list[RiskFlag] | None, typer.Option()] = None,
    risk_assessment_complete: Annotated[bool, typer.Option()] = False,
) -> None:
    decision = RoutingDecision.model_validate_json(sys.stdin.read())
    routing_config = RoutingConfig.model_validate_json(config.read_text())
    request = ExplorationRequest(
        decision=decision,
        config=routing_config,
        context=ExplorationContext(
            task_class=task_class,
            task_size=task_size,
            experiment_key=experiment_key,
            share_percent=share_percent,
            risk_flags=tuple(risk_flag or ()),
            risk_assessment_complete=risk_assessment_complete,
        ),
    )
    typer.echo(apply_exploration(request).model_dump_json(by_alias=True))


if __name__ == "__main__":
    typer.run(main)
