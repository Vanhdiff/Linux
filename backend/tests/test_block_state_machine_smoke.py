"""Smoke tests for BlockStateMachine.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_block_state_machine_smoke.py
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.domain.entities.block_state import BlockState, BlockStatus, BlockType
from app.domain.state_machine.block_state_machine import BlockStateMachine
from app.domain.state_machine.states import BlockStateEnum


def make_block(
    *,
    block_type: BlockType = BlockType.TEMPORARY,
    status: BlockStatus = BlockStatus.ACTIVE,
    expires_delta: timedelta | None = None,
    payload: dict | None = None,
) -> BlockState:
    now = datetime.now(timezone.utc)
    return BlockState(
        account_id=1,
        block_type=block_type,
        status=status,
        triggered_by=["cooling_off_active"],
        blocked_at=now,
        expires_at=now + (expires_delta or timedelta(hours=1)),
        payload=payload or {},
    )


def test_determine_state_without_existing_block() -> None:
    machine = BlockStateMachine()

    assert machine.determine_state([]) == BlockStateEnum.NORMAL
    assert machine.determine_state(["non_blocking_warning"]) == BlockStateEnum.WARNING
    assert machine.determine_state(["too_many_trades_today"]) == BlockStateEnum.FULL_DAY_BLOCK
    assert machine.determine_state(["max_daily_loss_reached"]) == BlockStateEnum.FULL_DAY_BLOCK


def test_existing_active_block_state_is_preserved() -> None:
    machine = BlockStateMachine()
    temporary = make_block(block_type=BlockType.TEMPORARY)
    full_day = make_block(block_type=BlockType.FULL_DAY)

    assert machine.determine_state([], temporary) == BlockStateEnum.TEMPORARY_BLOCK
    assert machine.determine_state([], full_day) == BlockStateEnum.FULL_DAY_BLOCK


def test_existing_expired_block_resolves() -> None:
    machine = BlockStateMachine()
    expired = make_block(expires_delta=timedelta(minutes=-1))

    assert machine.determine_state([], expired) == BlockStateEnum.RESOLVED


def test_terminal_existing_state_is_preserved() -> None:
    machine = BlockStateMachine()
    resolved = make_block(status=BlockStatus.RESOLVED)
    archived = make_block(status=BlockStatus.ARCHIVED, payload={"state": "archived"})

    assert machine.determine_state(["too_many_trades_today"], resolved) == BlockStateEnum.RESOLVED
    assert machine.determine_state(["too_many_trades_today"], archived) == BlockStateEnum.ARCHIVED


def test_calculate_expiry_and_create_block_state() -> None:
    machine = BlockStateMachine({"temporary_block_minutes": 15})
    before = datetime.now(timezone.utc)

    temporary_expiry = machine.calculate_expiry(BlockStateEnum.TEMPORARY_BLOCK)
    full_day_expiry = machine.calculate_expiry(BlockStateEnum.FULL_DAY_BLOCK)
    normal_expiry = machine.calculate_expiry(BlockStateEnum.NORMAL)
    block = machine.create_block_state(
        account_id=9,
        state=BlockStateEnum.TEMPORARY_BLOCK,
        triggered_by=["cooling_off_active"],
    )

    assert temporary_expiry is not None
    assert temporary_expiry > before
    assert temporary_expiry <= before + timedelta(minutes=16)
    assert full_day_expiry is not None
    assert normal_expiry is None
    assert block.account_id == 9
    assert block.block_type == BlockType.TEMPORARY
    assert block.triggered_by == ["cooling_off_active"]
    assert block.expires_at is not None


def test_create_block_state_rejects_non_blocking_states() -> None:
    machine = BlockStateMachine()

    try:
        machine.create_block_state(
            account_id=1,
            state=BlockStateEnum.WARNING,
            triggered_by=["non_blocking_warning"],
        )
    except ValueError as exc:
        assert "Cannot create persistent block state" in str(exc)
    else:
        raise AssertionError("Expected ValueError for non-blocking state")


def test_transition_validation_and_blocking_helpers() -> None:
    machine = BlockStateMachine()

    assert machine.can_transition(BlockStateEnum.WARNING, BlockStateEnum.TEMPORARY_BLOCK)
    assert machine.transition(BlockStateEnum.WARNING, BlockStateEnum.FULL_DAY_BLOCK) == BlockStateEnum.FULL_DAY_BLOCK
    assert machine.is_blocking(BlockStateEnum.TEMPORARY_BLOCK) is True
    assert machine.is_blocking(BlockStateEnum.FULL_DAY_BLOCK) is True
    assert machine.is_blocking(BlockStateEnum.WARNING) is False
    assert machine.get_block_description(BlockStateEnum.NORMAL) == "Trading allowed"

    try:
        machine.transition(BlockStateEnum.FULL_DAY_BLOCK, BlockStateEnum.WARNING)
    except ValueError as exc:
        assert "Invalid block state transition" in str(exc)
    else:
        raise AssertionError("Expected ValueError for invalid transition")


if __name__ == "__main__":
    test_determine_state_without_existing_block()
    test_existing_active_block_state_is_preserved()
    test_existing_expired_block_resolves()
    test_terminal_existing_state_is_preserved()
    test_calculate_expiry_and_create_block_state()
    test_create_block_state_rejects_non_blocking_states()
    test_transition_validation_and_blocking_helpers()
    print("test_block_state_machine_smoke: PASS")
