"""Smoke tests for EA communication contract metadata.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_ea_communication_contract_smoke.py
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.ea_communication_contract import (
    CONTRACT_VERSION,
    EACommunicationContract,
)


def test_ea_contract_exposes_pre_trade_validation_rules() -> None:
    contract = EACommunicationContract().build(api_prefix="/api")

    assert contract["contract_version"] == CONTRACT_VERSION
    assert contract["transport"] == "local_http"
    assert contract["method"] == "POST"
    assert contract["endpoint"] == "/api/guardrails/pre-trade/validate"
    assert contract["timeout_ms"] > 0
    assert contract["fail_policy"] == "deny_on_timeout_or_invalid_response"
    assert "account_id" in contract["request_required_fields"]
    assert "decision" in contract["response_required_fields"]
    assert contract["allow_values"] == ["ALLOW"]
    assert contract["deny_values"] == ["DENY"]
    assert contract["failure_action"] == "DENY"
    assert "connection_timeout" in contract["failure_modes"]
    assert contract["required_local_ea_behavior"]["on_timeout"] == "DENY"
    assert contract["required_local_ea_behavior"]["on_decision_allow"] == "ALLOW_ONLY_FOR_THIS_ATTEMPT"
    assert any("Proceed only" in item for item in contract["ea_rules"])


def test_fail_safe_response_validation_requires_explicit_allow() -> None:
    contract = EACommunicationContract()
    valid_allow = {
        "account_id": 1,
        "allowed": True,
        "blocked": False,
        "decision": "ALLOW",
        "trade_blocking_enabled": True,
        "reasons": [],
        "block_state": {"active": False},
        "checked_at": "2026-07-07T00:00:00",
        "request": {"account_id": 1},
    }
    explicit_deny = {**valid_allow, "allowed": False, "blocked": True, "decision": "DENY"}
    missing_field = dict(valid_allow)
    missing_field.pop("decision")

    assert contract.should_allow_response(valid_allow, http_status=200) is True
    assert contract.should_allow_response(explicit_deny, http_status=200) is False
    assert contract.should_allow_response(missing_field, http_status=200) is False
    assert contract.should_allow_response(valid_allow, http_status=500) is False
    assert contract.should_allow_response(None, http_status=200) is False


def test_ea_contract_handles_empty_api_prefix() -> None:
    contract = EACommunicationContract().build(api_prefix="")

    assert contract["endpoint"] == "/guardrails/pre-trade/validate"


if __name__ == "__main__":
    test_ea_contract_exposes_pre_trade_validation_rules()
    test_fail_safe_response_validation_requires_explicit_allow()
    test_ea_contract_handles_empty_api_prefix()
    print("test_ea_communication_contract_smoke: PASS")
