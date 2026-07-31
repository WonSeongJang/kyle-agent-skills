from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

SCRIPT = Path(__file__).parents[1] / "select_routing_pair.py"
CONFIG = Path(__file__).parents[2] / "references" / "routing-providers.json"


def load_router() -> ModuleType:
    spec = importlib.util.spec_from_file_location("select_routing_pair", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def quotas(kimi_weekly: float, openai_weekly: float) -> str:
    return json.dumps(
        {
            "generatedAt": 1_784_877_896_945,
            "reports": [
                {
                    "provider": "kimi",
                    "quota": {
                        "fiveHourPercent": 0,
                        "fiveHourResetAt": 1_784_894_501_935,
                        "weeklyPercent": kimi_weekly,
                        "weeklyResetAt": 1_785_121_301_935,
                    },
                },
                {
                    "provider": "openai",
                    "quota": {
                        "weeklyPercent": openai_weekly,
                        "weeklyResetAt": 1_785_278_469_000,
                    },
                },
            ],
        }
    )


def test_kimi_sol_when_glm_is_unavailable() -> None:
    router = load_router()
    decision = router.select_pair(
        router.SelectionRequest(
            config_path=CONFIG,
            quota_json=quotas(kimi_weekly=74, openai_weekly=58),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"zai", "anthropic"}),
            now_ms=1_784_877_896_945,
        )
    )
    assert decision.developer.provider == "kimi"
    assert decision.reviewer.provider == "openai"


def test_terra_sol_only_after_kimi_reserve_would_be_breached() -> None:
    router = load_router()
    decision = router.select_pair(
        router.SelectionRequest(
            config_path=CONFIG,
            quota_json=quotas(kimi_weekly=96, openai_weekly=58),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"zai", "anthropic"}),
            now_ms=1_784_877_896_945,
        )
    )
    assert decision.developer.model == "gpt-5.6-terra"
    assert decision.reviewer.model == "gpt-5.6-sol"
    assert decision.same_family is True


def test_new_provider_is_considered_without_code_changes(tmp_path: Path) -> None:
    router = load_router()
    raw = json.loads(CONFIG.read_text())
    raw["providers"].append(
        {
            "id": "future",
            "family": "future",
            "quotaKey": None,
            "enabled": True,
            "weeklyReservePercent": 5,
            "models": [
                {
                    "id": "future-dev",
                    "role": "developer",
                    "effort": "medium",
                    "quality": 99,
                    "command": "future-cli",
                }
            ],
        }
    )
    config = tmp_path / "providers.json"
    config.write_text(json.dumps(raw))
    decision = router.select_pair(
        router.SelectionRequest(
            config_path=config,
            quota_json=quotas(kimi_weekly=74, openai_weekly=58),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"zai", "anthropic"}),
            now_ms=1_784_877_896_945,
        )
    )
    assert decision.developer.provider == "future"
    assert decision.reviewer.provider == "openai"


def test_same_model_never_reviews_itself() -> None:
    router = load_router()
    decision = router.select_pair(
        router.SelectionRequest(
            config_path=CONFIG,
            quota_json=quotas(kimi_weekly=74, openai_weekly=58),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"zai"}),
            now_ms=1_784_877_896_945,
        )
    )
    assert all(
        pair.developer.model != pair.reviewer.model
        for pair in decision.ranked_pairs
    )
    fallback_models = [
        (pair.developer.model, pair.reviewer.model)
        for pair in decision.ranked_pairs
    ]
    assert fallback_models.index(("gpt-5.6-terra", "gpt-5.6-sol")) < fallback_models.index(
        ("gpt-5.6-terra", "kimi/k3[1m]")
    )


def test_weekly_reserve_is_released_during_last_day_before_reset() -> None:
    router = load_router()
    provider = router.RoutingConfig.model_validate_json(CONFIG.read_text()).providers[2]
    now_ms = 1_784_877_896_945
    far_health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(weeklyPercent=76, weeklyResetAt=now_ms + 2 * 86_400_000),
        now_ms,
    )
    near_health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(weeklyPercent=76, weeklyResetAt=now_ms + 12 * 3_600_000),
        now_ms,
    )
    assert far_health.last_resort is True
    assert near_health.last_resort is False
    assert "weekly_reserve=10.00" in near_health.reasons


def test_weekly_reset_urgency_adds_linear_score_during_last_day() -> None:
    router = load_router()
    provider = router.RoutingConfig.model_validate_json(CONFIG.read_text()).providers[2]
    now_ms = 1_784_877_896_945
    far_health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(weeklyPercent=20, weeklyResetAt=now_ms + 2 * 86_400_000),
        now_ms,
    )
    near_health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(weeklyPercent=20, weeklyResetAt=now_ms + 12 * 3_600_000),
        now_ms,
    )

    assert near_health.score == far_health.score + 7.5
    assert "weekly_reset_urgency=7.50" in near_health.reasons
    assert all(not reason.startswith("weekly_reset_urgency=") for reason in far_health.reasons)


def test_weekly_reset_urgency_does_not_revive_exhausted_provider() -> None:
    router = load_router()
    provider = router.RoutingConfig.model_validate_json(CONFIG.read_text()).providers[2]
    now_ms = 1_784_877_896_945
    health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(weeklyPercent=99, weeklyResetAt=now_ms + 60_000),
        now_ms,
    )

    assert health.available is False
    assert health.reasons == ("weekly_exhausted",)


def test_five_hour_headroom_relaxes_from_1_5_to_1_near_reset() -> None:
    router = load_router()
    provider = router.RoutingConfig.model_validate_json(CONFIG.read_text()).providers[0]
    now_ms = 1_784_877_896_945
    far_health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(fiveHourPercent=93, fiveHourResetAt=now_ms + 2 * 3_600_000),
        now_ms,
    )
    near_health = router.quota_health(
        provider,
        5,
        router.QuotaMetrics(fiveHourPercent=93, fiveHourResetAt=now_ms + 30 * 60_000),
        now_ms,
    )
    assert far_health.last_resort is True
    assert near_health.last_resort is False
    assert "five_hour_headroom=1.25" in near_health.reasons


def test_fresh_rottie_quota_overrides_opencodex_provider() -> None:
    router = load_router()
    now_ms = 1_784_877_896_945
    fallback = router.QuotaResponse.model_validate_json(quotas(74, 58))
    rottie = router.QuotaResponse.model_validate(
        {
            "generatedAt": now_ms,
            "reports": [
                {
                    "provider": "openai",
                    "updatedAt": now_ms - 60_000,
                    "quota": {"weeklyPercent": 12},
                },
                {
                    "provider": "anthropic",
                    "updatedAt": now_ms - 60_000,
                    "quota": {"weeklyPercent": 64},
                },
            ],
        }
    )

    merged = router.merge_quota_sources(fallback, rottie, now_ms)
    by_provider = {report.provider: report for report in merged.reports}

    assert by_provider["openai"].quota.weekly_used == 12
    assert by_provider["anthropic"].quota.weekly_used == 64
    assert by_provider["kimi"].quota.weekly_used == 74


def test_stale_rottie_provider_does_not_override_fallback() -> None:
    router = load_router()
    now_ms = 1_784_877_896_945
    fallback = router.QuotaResponse.model_validate_json(quotas(74, 58))
    rottie = router.QuotaResponse.model_validate(
        {
            "generatedAt": now_ms,
            "reports": [
                {
                    "provider": "openai",
                    "updatedAt": now_ms - router.ROTTIE_FRESHNESS_MS - 1,
                    "quota": {"weeklyPercent": 12},
                }
            ],
        }
    )

    merged = router.merge_quota_sources(fallback, rottie, now_ms)
    by_provider = {report.provider: report for report in merged.reports}

    assert by_provider["openai"].quota.weekly_used == 58


def experiment_key(router: ModuleType, enabled: bool) -> str:
    config = router.RoutingConfig.model_validate_json(CONFIG.read_text())
    opus = next(
        model
        for provider in config.providers
        if provider.id == "anthropic"
        for model in provider.models
        if model.role is router.Role.DEVELOPER
    )
    return next(
        f"card-{index}"
        for index in range(1_000)
        if (router.experiment_bucket(opus, f"card-{index}") < opus.experiment_share_percent)
        is enabled
    )


def experiment_quotas(now_ms: int, anthropic_weekly: float = 20) -> str:
    return json.dumps(
        {
            "generatedAt": now_ms,
            "reports": [
                {
                    "provider": "openai",
                    "quota": {
                        "weeklyPercent": 20,
                        "weeklyResetAt": now_ms + 5 * 86_400_000,
                    },
                },
                {
                    "provider": "anthropic",
                    "quota": {
                        "fiveHourPercent": 2,
                        "fiveHourResetAt": now_ms + 4 * 3_600_000,
                        "weeklyPercent": anthropic_weekly,
                        "weeklyResetAt": now_ms + 5 * 86_400_000,
                    },
                },
            ],
        }
    )


def test_opus_experiment_slot_uses_sol_reviewer() -> None:
    router = load_router()
    now_ms = 1_784_877_896_945
    key = experiment_key(router, enabled=True)

    decision = router.select_pair(
        router.SelectionRequest(
            config_path=CONFIG,
            quota_json=experiment_quotas(now_ms),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"kimi", "zai"}),
            now_ms=now_ms,
            experiment_key=key,
        )
    )

    assert decision.developer.model == "opus"
    assert decision.reviewer.model == "gpt-5.6-sol"
    assert "experiment_share=20" in decision.reasons


def test_opus_experiment_is_closed_outside_twenty_percent_slot() -> None:
    router = load_router()
    now_ms = 1_784_877_896_945
    key = experiment_key(router, enabled=False)

    decision = router.select_pair(
        router.SelectionRequest(
            config_path=CONFIG,
            quota_json=experiment_quotas(now_ms),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"kimi", "zai"}),
            now_ms=now_ms,
            experiment_key=key,
        )
    )

    assert decision.developer.model == "gpt-5.6-terra"


def test_opus_experiment_respects_anthropic_quota_exhaustion() -> None:
    router = load_router()
    now_ms = 1_784_877_896_945
    key = experiment_key(router, enabled=True)

    decision = router.select_pair(
        router.SelectionRequest(
            config_path=CONFIG,
            quota_json=experiment_quotas(now_ms, anthropic_weekly=99),
            task_size=router.TaskSize.HEAVY,
            unavailable_providers=frozenset({"kimi", "zai"}),
            now_ms=now_ms,
            experiment_key=key,
        )
    )

    assert decision.developer.model == "gpt-5.6-terra"
