"""Smoke tests for MT5 EA skeleton contract text.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_mt5_ea_skeleton_contract_smoke.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EA_FILE = ROOT / "mt5" / "Experts" / "TradingDeskGuardEA.mq5"
README_FILE = ROOT / "mt5" / "README.md"


def test_ea_skeleton_contains_fail_safe_policy() -> None:
    content = EA_FILE.read_text(encoding="utf-8")

    assert "ValidateBeforeTrade" in content
    assert "PostPreTradeValidation" in content
    assert "ShouldAllowBackendResponse" in content


def test_ea_skeleton_has_reactive_manual_trade_protection() -> None:
    content = EA_FILE.read_text(encoding="utf-8")

    assert "IsBackendBlocked" in content
    assert "block_" in content
    assert "DeleteAllPendingOrders" in content
    assert "CloseAllOpenPositions" in content
    assert "trade.PositionClose" in content
    assert "trade.OrderDelete" in content
    assert "WriteHeartbeat" in content
    assert "IsoUtcNow" in content
    assert "EnforceBlockState" in content
    assert "OnTradeTransaction" in content
    assert "payload += metadataJson;" in content
    assert "LoadRuntimeConfig" in content
    assert "ProcessCommandFile" in content
    assert "ea_config.json" in content
    assert "ea_command.json" in content
    assert "runtimeBackendBaseUrl" in content
    assert "runtimeAccountId" in content
    assert "backend down" in content
    assert "timeout" in content
    assert "non-200 response" in content
    assert "invalid JSON" in content
    assert "decision != \"ALLOW\"" in content
    assert "allowed != true" in content
    assert "return false" in content


def test_ea_skeleton_uses_webrequest_and_still_denies_on_error() -> None:
    content = EA_FILE.read_text(encoding="utf-8")

    assert "WebRequest(" in content
    assert "httpStatus == -1" in content
    assert "return false;" in content
    assert "Add backend URL to MT5 allowed WebRequest list" in content
    assert "ShouldAllowBackendResponse" in content


def test_mt5_readme_documents_contract_endpoints() -> None:
    content = README_FILE.read_text(encoding="utf-8")

    assert "GET /guardrails/pre-trade/contract" in content
    assert "POST /guardrails/pre-trade/validate" in content
    assert "block_{account_id}.json" in content
    assert "ea_status.json" in content
    assert "ea_config.json" in content
    assert "ea_command.json" in content
    assert "Every other case must deny locally" in content
    assert "Allow WebRequest for listed URL" in content
    assert "Reactive protection for manual MT5 orders" in content
    assert "cannot prevent a user from clicking Buy/Sell manually" in content


if __name__ == "__main__":
    test_ea_skeleton_contains_fail_safe_policy()
    test_ea_skeleton_uses_webrequest_and_still_denies_on_error()
    test_ea_skeleton_has_reactive_manual_trade_protection()
    test_mt5_readme_documents_contract_endpoints()
    print("test_mt5_ea_skeleton_contract_smoke: PASS")
