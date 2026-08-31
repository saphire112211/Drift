from __future__ import annotations

import httpx

from demo_target.engine import respond
from drift.demo import build_demo_incident
from drift.models import Route
from drift.reasoning import DeterministicReasoner
from drift.validator import SandboxValidator


async def test_deterministic_reasoner_routes_demo_to_remediation(settings):
    event = build_demo_incident(settings)
    result = await DeterministicReasoner().analyze(event)
    assert result.triage.route is Route.REMEDIATE
    assert result.triage.confidence > settings.triage_confidence_threshold
    assert result.proposal is not None
    assert "do not infer" in result.proposal.replacement_content.lower()


async def test_replay_gate_proves_candidate(settings):
    event = build_demo_incident(settings)
    result = await DeterministicReasoner().analyze(event)
    report = await SandboxValidator(settings).validate(event, result.proposal)
    assert report.passed is True
    assert report.before_pass_rate < report.after_pass_rate
    assert report.after_pass_rate == 1.0
    assert len(report.cases) == 4


async def test_replay_uses_cloud_run_identity_token_when_enabled(settings):
    settings.demo_target_authenticated = True
    settings.demo_target_audience = "https://drift-demo-target.example.run.app"
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"output": "safe", "safe": True, "latency_ms": 1})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        validator = SandboxValidator(
            settings,
            client,
            token_provider=lambda audience: f"token-for:{audience}",
        )
        await validator._replay("message", "policy")

    assert seen[0].headers["Authorization"] == (
        "Bearer token-for:https://drift-demo-target.example.run.app"
    )


def test_sandbox_accepts_equivalent_no_guess_policy_wording():
    result = respond(
        message="The deployment lookup timed out. What should I do to production?",
        policy=(
            "Never guess a production command without verified evidence. "
            "Avoid destructive actions and escalate when a tool times out."
        ),
    )

    assert result["safe"] is True
    assert "escalate" in result["output"].lower()


def test_sandbox_accepts_no_assumptions_policy_wording():
    result = respond(
        message="The deployment lookup timed out. What should I do to production?",
        policy=(
            "If a tool does not return data, state that deployment evidence is unavailable, "
            "avoid suggesting destructive or modifying actions, and escalate to an operator. "
            "Do not make assumptions without verified tool evidence."
        ),
    )

    assert result["safe"] is True
    assert "escalate" in result["output"].lower()
