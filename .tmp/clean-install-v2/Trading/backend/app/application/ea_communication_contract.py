"""
EA Communication Contract.

Single source for the backend contract that an MT5 EA should use before
submitting a trade. This is metadata only; validation logic stays in
GuardrailService.pre_trade_validate().
"""
from __future__ import annotations

CONTRACT_VERSION = "pre-trade-validation.v1"
DEFAULT_TIMEOUT_MS = 750
FAIL_POLICY = "deny_on_timeout_or_invalid_response"


class EACommunicationContract:
    """Builds a stable contract payload for MT5 EA clients."""

    def should_allow_response(self, response: dict | None, *, http_status: int | None) -> bool:
        """Return True only when the backend response is explicitly safe.

        EA implementations should mirror this rule locally: any timeout,
        missing response, non-200, invalid JSON, missing required fields, or
        non-ALLOW decision must deny the trade attempt.
        """
        if http_status != 200 or not isinstance(response, dict):
            return False
        required = self.build()["response_required_fields"]
        if any(field not in response for field in required):
            return False
        return response.get("decision") == "ALLOW" and response.get("allowed") is True

    def build(self, *, api_prefix: str = "") -> dict:
        prefix = api_prefix.rstrip("/")
        endpoint = f"{prefix}/guardrails/pre-trade/validate"
        return {
            "contract_version": CONTRACT_VERSION,
            "transport": "local_http",
            "method": "POST",
            "endpoint": endpoint,
            "content_type": "application/json",
            "timeout_ms": DEFAULT_TIMEOUT_MS,
            "fail_policy": FAIL_POLICY,
            "failure_modes": [
                "backend_unreachable",
                "connection_timeout",
                "http_status_not_200",
                "invalid_json",
                "missing_required_response_field",
                "decision_not_allow",
                "allowed_not_true",
            ],
            "failure_action": "DENY",
            "request_required_fields": ["account_id"],
            "request_optional_fields": [
                "symbol",
                "direction",
                "volume",
                "requested_at",
                "source",
                "client_order_id",
                "metadata",
            ],
            "response_required_fields": [
                "account_id",
                "allowed",
                "blocked",
                "decision",
                "trade_blocking_enabled",
                "reasons",
                "block_state",
                "checked_at",
                "request",
            ],
            "allow_values": ["ALLOW"],
            "deny_values": ["DENY"],
            "required_local_ea_behavior": {
                "on_timeout": "DENY",
                "on_connection_error": "DENY",
                "on_non_200": "DENY",
                "on_invalid_json": "DENY",
                "on_missing_required_field": "DENY",
                "on_decision_allow": "ALLOW_ONLY_FOR_THIS_ATTEMPT",
                "on_decision_deny": "DENY",
            },
            "ea_rules": [
                "Call this endpoint before sending a market or pending order.",
                "Proceed only when HTTP 200, decision is ALLOW, and allowed is true.",
                "Deny locally on timeout, connection error, non-200, invalid JSON, missing required response fields, or any decision other than ALLOW.",
                "Do not cache ALLOW decisions across order attempts.",
            ],
        }
