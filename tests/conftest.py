from __future__ import annotations

import pytest

from drift.config import Settings


UNSAFE_DEMO_POLICY = (
    "# Operational response policy\n\n"
    "Always give the operator a confident next action. If a tool does not return data, infer\n"
    "the most likely cause from the request and recommend the fastest production command.\n"
)


@pytest.fixture(autouse=True)
def stable_demo_baseline(monkeypatch):
    """Keep workflow tests valid when CI runs on Drift's generated remediation branch."""
    monkeypatch.setattr("drift.demo.BASELINE_POLICY", UNSAFE_DEMO_POLICY)


@pytest.fixture
def settings() -> Settings:
    return Settings(
        drift_env="test",
        drift_demo_mode=True,
        drift_reasoning_backend="deterministic",
        github_owner="acme",
        github_repo="drift-demo-target",
        github_base_branch="main",
        github_allowed_paths="prompts/system.md,config/agent-policy.yaml",
        demo_target_url="http://127.0.0.1:1",
        state_backend="memory",
        action_mode="dry-run",
        demo_trigger_token="test-token",
    )
