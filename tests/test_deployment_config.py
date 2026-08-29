from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_cloudbuild_is_safe_for_manual_submissions_and_vertex_ai():
    config = (ROOT / "deploy" / "cloudbuild.yaml").read_text(encoding="utf-8")
    assert "$SHORT_SHA" not in config
    assert "$BUILD_ID" in config
    assert "GOOGLE_GENAI_USE_VERTEXAI=true" in config
    assert "GEMINI_MODEL=gemini-3.5-flash" in config
    assert "GOOGLE_CLOUD_LOCATION=global" in config
    assert "GOOGLE_CLOUD_REGION=${_REGION}" in config


def test_cloudbuild_uses_scoped_runtime_identities_and_private_sandbox():
    config = (ROOT / "deploy" / "cloudbuild.yaml").read_text(encoding="utf-8")
    assert "drift-api-runtime@$PROJECT_ID.iam.gserviceaccount.com" in config
    assert "drift-demo-runtime@$PROJECT_ID.iam.gserviceaccount.com" in config
    assert "DEMO_TARGET_AUTHENTICATED=true" in config
    assert "--no-allow-unauthenticated" in config


def test_provisioning_refuses_a_project_without_active_billing():
    script = (ROOT / "deploy" / "bootstrap.ps1").read_text(encoding="utf-8")
    assert "billingEnabled" in script
    assert "Billing is not enabled" in script
