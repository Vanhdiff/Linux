from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base
from app.domain.entities.block_state import (
    BlockState as DomainBlockState,
    BlockStatus,
    BlockType,
)
from app.domain.state_machine.block_state_machine import BlockStateMachine
from app.domain.state_machine.states import BlockStateEnum
from app.infrastructure.persistence.block_repository import BlockRepository
from app.models import BlockState as DBBlockState
from app.models import TradingAccount


def _make_db_session():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return engine, SessionLocal()


def test_block_state_normalizes_db_values_and_lifecycle_state():
    blocked_at = datetime(2026, 7, 1, 8, 30, 0)
    resolved_at = datetime(2026, 7, 1, 9, 0, 0)
    db_model = DBBlockState(
        id=11,
        account_id=7,
        block_type="full_day",
        triggered_by=["too_many_trades_today"],
        blocked_at=blocked_at,
        expires_at=blocked_at + timedelta(hours=16),
        resolved_at=resolved_at,
        auto_resolved=True,
        payload={"state": "archived"},
    )

    block = DomainBlockState.from_db_model(db_model)

    assert block.block_type is BlockType.FULL_DAY
    assert block.status is BlockStatus.ARCHIVED
    assert block.current_state() is BlockStateEnum.ARCHIVED
    assert block.resolved_by == "archive"
    assert block.blocked_at.tzinfo is not None
    assert block.expires_at.tzinfo is not None


def test_block_state_machine_transitions_and_rejects_invalid_transition():
    machine = BlockStateMachine()
    existing_block = DomainBlockState(
        account_id=42,
        block_type=BlockType.TEMPORARY,
        status=BlockStatus.ACTIVE,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=30),
    )

    assert machine.determine_state([], None) is BlockStateEnum.NORMAL
    assert machine.determine_state(["risk_too_high"], None) is BlockStateEnum.TEMPORARY_BLOCK
    assert (
        machine.determine_state(["max_daily_loss_reached"], None)
        is BlockStateEnum.FULL_DAY_BLOCK
    )
    assert machine.determine_state([], existing_block) is BlockStateEnum.TEMPORARY_BLOCK
    assert machine.can_transition(BlockStateEnum.NORMAL, BlockStateEnum.WARNING)
    assert machine.can_transition(
        BlockStateEnum.TEMPORARY_BLOCK,
        BlockStateEnum.FULL_DAY_BLOCK,
    )

    try:
        machine.transition(BlockStateEnum.FULL_DAY_BLOCK, BlockStateEnum.WARNING)
    except ValueError:
        pass
    else:
        raise AssertionError("Expected invalid block state transition to fail")


def test_block_repository_cleans_expired_blocks_and_restores_active_blocks():
    engine, db_session = _make_db_session()
    try:
        _assert_block_repository_cleans_expired_blocks_and_restores_active_blocks(
            db_session
        )
    finally:
        db_session.close()
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


def _assert_block_repository_cleans_expired_blocks_and_restores_active_blocks(
    db_session,
):
    account = TradingAccount(login="10001", name="Test account")
    db_session.add(account)
    db_session.commit()

    now = datetime.now(timezone.utc)
    active_block = DBBlockState(
        account_id=account.id,
        block_type="temporary",
        triggered_by=["risk_too_high"],
        blocked_at=now - timedelta(minutes=5),
        expires_at=now + timedelta(minutes=30),
        payload={"state": "temporary_block"},
    )
    expired_block = DBBlockState(
        account_id=account.id,
        block_type="full_day",
        triggered_by=["too_many_trades_today"],
        blocked_at=now - timedelta(days=1),
        expires_at=now - timedelta(minutes=1),
        payload={"state": "full_day_block"},
    )
    db_session.add_all([active_block, expired_block])
    db_session.commit()

    repo = BlockRepository(db_session)

    cleaned = repo.cleanup_expired_blocks(account_id=account.id)
    active = repo.restore_active_blocks(account_id=account.id)

    assert len(cleaned) == 1
    assert cleaned[0].status is BlockStatus.RESOLVED
    assert cleaned[0].resolved_by == "auto"
    assert len(active) == 1
    assert active[0].status is BlockStatus.ACTIVE
    assert active[0].block_type is BlockType.TEMPORARY
    assert repo.count_active_blocks() == 1


if __name__ == "__main__":
    test_block_state_normalizes_db_values_and_lifecycle_state()
    test_block_state_machine_transitions_and_rejects_invalid_transition()
    test_block_repository_cleans_expired_blocks_and_restores_active_blocks()
    print("test_block_trade_phase1a: PASS")
