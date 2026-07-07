"""Smoke tests for BlockRepository.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_block_repository_smoke.py
"""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.domain.entities.block_state import BlockState, BlockStatus, BlockType
from app.infrastructure.persistence.block_repository import BlockRepository
from app.models import TradingAccount


def build_session():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = SessionLocal()
    account = TradingAccount(
        name="Repository Smoke Account",
        broker="Test Broker",
        server="Test Server",
        login="repo-smoke-1",
        currency="USD",
        timezone="UTC",
        is_active=True,
    )
    session.add(account)
    session.commit()
    session.refresh(account)
    return session, account.id


def make_block(account_id: int, *, expires_delta: timedelta | None = None) -> BlockState:
    now = datetime.now(timezone.utc)
    return BlockState(
        account_id=account_id,
        block_type=BlockType.TEMPORARY,
        triggered_by=["cooling_off_active"],
        blocked_at=now,
        expires_at=now + (expires_delta or timedelta(hours=1)),
        payload={"state": "TEMPORARY_BLOCK"},
    )


def test_save_and_get_active_block() -> None:
    session, account_id = build_session()
    try:
        repo = BlockRepository(session)
        saved = repo.save(make_block(account_id))

        active = repo.get_active_block(account_id)

        assert saved.id is not None
        assert active is not None
        assert active.id == saved.id
        assert active.account_id == account_id
        assert active.block_type == BlockType.TEMPORARY
        assert active.status == BlockStatus.ACTIVE
        assert active.triggered_by == ["cooling_off_active"]
    finally:
        session.close()


def test_update_existing_block() -> None:
    session, account_id = build_session()
    try:
        repo = BlockRepository(session)
        saved = repo.save(make_block(account_id))
        saved.block_type = BlockType.FULL_DAY
        saved.triggered_by = ["too_many_trades_today"]
        saved.payload = {"state": "FULL_DAY_BLOCK"}

        updated = repo.save(saved)
        active = repo.get_active_block(account_id)

        assert updated.id == saved.id
        assert active is not None
        assert active.block_type == BlockType.FULL_DAY
        assert active.triggered_by == ["too_many_trades_today"]
        assert active.payload["state"] == "FULL_DAY_BLOCK"
    finally:
        session.close()


def test_manual_resolve_removes_active_block_but_keeps_history() -> None:
    session, account_id = build_session()
    try:
        repo = BlockRepository(session)
        saved = repo.save(make_block(account_id))

        resolved = repo.resolve_block(account_id, manually=True)
        active = repo.get_active_block(account_id)
        history = repo.get_block_history(account_id)

        assert resolved is True
        assert active is None
        assert history[0].id == saved.id
        assert history[0].status == BlockStatus.RESOLVED
        assert history[0].resolved_by == "manual"
    finally:
        session.close()


def test_expired_block_auto_resolves_on_get_active_block() -> None:
    session, account_id = build_session()
    try:
        repo = BlockRepository(session)
        saved = repo.save(make_block(account_id, expires_delta=timedelta(minutes=-1)))

        active = repo.get_active_block(account_id)
        history = repo.get_block_history(account_id)

        assert active is None
        assert history[0].id == saved.id
        assert history[0].status == BlockStatus.RESOLVED
        assert history[0].resolved_by == "auto"
    finally:
        session.close()


def test_cleanup_expired_blocks_only_resolves_expired_account_blocks() -> None:
    session, account_id = build_session()
    try:
        repo = BlockRepository(session)
        expired = repo.save(make_block(account_id, expires_delta=timedelta(minutes=-1)))
        active = repo.save(make_block(account_id, expires_delta=timedelta(hours=1)))

        cleaned = repo.cleanup_expired_blocks(account_id=account_id)
        still_active = repo.get_active_block(account_id)

        assert [item.id for item in cleaned] == [expired.id]
        assert still_active is not None
        assert still_active.id == active.id
        assert still_active.status == BlockStatus.ACTIVE
    finally:
        session.close()


if __name__ == "__main__":
    test_save_and_get_active_block()
    test_update_existing_block()
    test_manual_resolve_removes_active_block_but_keeps_history()
    test_expired_block_auto_resolves_on_get_active_block()
    test_cleanup_expired_blocks_only_resolves_expired_account_blocks()
    print("test_block_repository_smoke: PASS")
