"""Smoke tests for BlockExecutor.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_block_executor_smoke.py
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.block_decision_engine import BlockDecision
from app.application.block_executor import (
    AuditLogger,
    BlockEventType,
    BlockExecutor,
    EventDispatcher,
)
from app.domain.entities.block_state import BlockState, BlockType
from app.domain.state_machine.states import BlockStateEnum


class FakeBlockRepository:
    def __init__(self, fail_on_save: bool = False):
        self.fail_on_save = fail_on_save
        self.saved_blocks = []
        self.active_block = None

    def save(self, block):
        if self.fail_on_save:
            raise RuntimeError("save failed")
        if block.id is None:
            block.id = 42
        self.saved_blocks.append(block)
        self.active_block = block
        return block

    def get_active_block(self, account_id):
        return self.active_block


class FakeAuditLogger(AuditLogger):
    def __init__(self):
        self.applied = []
        self.enforcement_ready = []

    def log_block_applied(self, *args, **kwargs):
        self.applied.append({"args": args, "kwargs": kwargs})

    def log_enforcement_ready(self, *args, **kwargs):
        self.enforcement_ready.append({"args": args, "kwargs": kwargs})


def make_block() -> BlockState:
    return BlockState(
        account_id=7,
        block_type=BlockType.FULL_DAY,
        triggered_by=["too_many_trades_today"],
        blocked_at=datetime.now(timezone.utc),
        expires_at=datetime.now(timezone.utc) + timedelta(hours=6),
    )


def make_executor(repo: FakeBlockRepository, audit: FakeAuditLogger | None = None) -> BlockExecutor:
    executor = BlockExecutor.__new__(BlockExecutor)
    executor._db = None
    executor._repo = repo
    executor._event_dispatcher = EventDispatcher()
    executor._audit_logger = audit or FakeAuditLogger()
    executor._mt5_prepared = False
    return executor


def test_no_block_decision_returns_success_without_persisting() -> None:
    repo = FakeBlockRepository()
    executor = make_executor(repo)
    decision = BlockDecision(
        state=BlockStateEnum.NORMAL,
        trade_blocked=False,
        reasons=[],
        block_state=None,
    )

    result = executor.execute(decision)

    assert result.success is True
    assert result.block_id is None
    assert result.events_dispatched == []
    assert repo.saved_blocks == []
    assert executor._mt5_prepared is False


def test_block_decision_persists_dispatches_and_prepares_mt5() -> None:
    repo = FakeBlockRepository()
    audit = FakeAuditLogger()
    executor = make_executor(repo, audit)
    captured_events = []
    executor.on_block_applied(captured_events.append)
    block = make_block()
    decision = BlockDecision(
        state=BlockStateEnum.FULL_DAY_BLOCK,
        trade_blocked=True,
        reasons=[{"rule_code": "too_many_trades_today"}],
        block_state=block,
    )

    result = executor.execute(decision)

    assert result.success is True
    assert result.block_id == 42
    assert result.block_state["account_id"] == 7
    assert result.block_state["block_type"] == "full_day"
    assert result.block_state["triggered_by"] == ["too_many_trades_today"]
    assert result.events_dispatched == [BlockEventType.BLOCK_APPLIED]
    assert len(repo.saved_blocks) == 1
    assert len(captured_events) == 1
    assert captured_events[0].account_id == 7
    assert captured_events[0].block_id == 42
    assert audit.applied
    assert audit.enforcement_ready
    assert executor._mt5_prepared is True


def test_repository_error_returns_failed_execution_result() -> None:
    repo = FakeBlockRepository(fail_on_save=True)
    executor = make_executor(repo)
    decision = BlockDecision(
        state=BlockStateEnum.FULL_DAY_BLOCK,
        trade_blocked=True,
        reasons=[{"rule_code": "too_many_trades_today"}],
        block_state=make_block(),
    )

    result = executor.execute(decision)

    assert result.success is False
    assert "save failed" in result.error
    assert result.block_id is None
    assert result.events_dispatched == []
    assert executor._mt5_prepared is False


if __name__ == "__main__":
    test_no_block_decision_returns_success_without_persisting()
    test_block_decision_persists_dispatches_and_prepares_mt5()
    test_repository_error_returns_failed_execution_result()
    print("test_block_executor_smoke: PASS")
