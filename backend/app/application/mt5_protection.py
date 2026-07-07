"""
MT5 Protection - File-based communication with MT5 EA.

Creates:
- MT5BlockEnforcer: Coordinates blocking enforcement
- EACommunicationLayer: File-based IPC with MT5 EA
- BlockStateSync: Synchronizes BlockState with MT5

Communication via shared files:
- block_{account_id}.json: Current block state
- ea_status.json: EA connection status
"""
import json
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from app.config import settings
from app.infrastructure.persistence.block_repository import BlockRepository

logger = logging.getLogger(__name__)


# Default MT5 data directory
MT5_DATA_DIR = Path.home() / "TradingDesk" / "mt5_data"


@dataclass
class EAStatus:
    """Status of the MT5 EA connection."""
    connected: bool = False
    last_heartbeat: datetime | None = None
    version: str = ""
    account_id: int | None = None
    error: str = ""


@dataclass
class BlockFilePayload:
    """Block state file format for EA communication."""
    account_id: int
    blocked: bool
    block_type: str | None  # "temporary" or "full_day"
    blocked_at: str | None
    expires_at: str | None
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    triggered_by: list[str] = field(default_factory=list)
    reasons: list[dict] = field(default_factory=list)


class EACommunicationLayer:
    """
    File-based communication layer with MT5 EA.

    Writes block state to files that the MT5 EA reads.
    No network calls - purely file-based IPC.
    """

    def __init__(self, data_dir: Path | None = None):
        """
        Initialize EA communication layer.

        Args:
            data_dir: Directory for shared files (default: TradingDesk/mt5_data)
        """
        self._data_dir = data_dir or MT5_DATA_DIR
        self._ensure_directory()

    def _ensure_directory(self) -> None:
        """Ensure data directory exists."""
        self._data_dir.mkdir(parents=True, exist_ok=True)

    def _block_file_path(self, account_id: int) -> Path:
        """Get path to block state file for account."""
        return self._data_dir / f"block_{account_id}.json"

    def _status_file_path(self) -> Path:
        """Get path to EA status file."""
        return self._data_dir / "ea_status.json"

    def write_block_state(
        self,
        account_id: int,
        blocked: bool,
        block_type: str | None,
        blocked_at: datetime | None,
        expires_at: datetime | None,
        triggered_by: list[str],
        reasons: list[dict],
    ) -> bool:
        """
        Write block state to file for EA to read.

        Args:
            account_id: Trading account ID
            blocked: Whether trading is blocked
            block_type: Type of block ("temporary" or "full_day")
            blocked_at: When block started
            expires_at: When block expires
            triggered_by: List of rule codes that triggered block
            reasons: List of reason objects

        Returns:
            True if write succeeded
        """
        try:
            # Calculate remaining seconds
            remaining_seconds = 0
            if expires_at:
                now = datetime.now(timezone.utc)
                if expires_at.tzinfo is None:
                    expires_at = expires_at.replace(tzinfo=timezone.utc)
                delta = expires_at - now
                remaining_seconds = max(0, int(delta.total_seconds()))

            payload = BlockFilePayload(
                account_id=account_id,
                blocked=blocked,
                block_type=block_type,
                blocked_at=blocked_at.isoformat() if blocked_at else None,
                expires_at=expires_at.isoformat() if expires_at else None,
                remaining_seconds=remaining_seconds,
                triggered_by=triggered_by,
                reasons=reasons,
                updated_at=datetime.now(timezone.utc).isoformat(),
            )

            file_path = self._block_file_path(account_id)
            temp_path = file_path.with_suffix('.tmp')

            with open(temp_path, 'w', encoding='utf-8') as f:
                json.dump(payload.__dict__, f, indent=2)

            # Atomic rename
            temp_path.replace(file_path)

            logger.debug(f"Wrote block state for account {account_id}: blocked={blocked}")
            return True

        except Exception as e:
            logger.error(f"Failed to write block state for account {account_id}: {e}")
            return False

    def read_ea_status(self) -> EAStatus:
        """
        Read EA status from file.

        Returns:
            EAStatus with current connection state
        """
        try:
            status_file = self._status_file_path()
            if not status_file.exists():
                return EAStatus(connected=False, error="Status file not found")

            with open(status_file, 'r', encoding='utf-8') as f:
                data = json.load(f)

            last_heartbeat = None
            if data.get("last_heartbeat"):
                try:
                    last_heartbeat = datetime.fromisoformat(data["last_heartbeat"])
                except (ValueError, TypeError):
                    pass

            return EAStatus(
                connected=data.get("connected", False),
                last_heartbeat=last_heartbeat,
                version=data.get("version", ""),
                account_id=data.get("account_id"),
                error=data.get("error", ""),
            )

        except Exception as e:
            return EAStatus(connected=False, error=str(e))

    def clear_block_state(self, account_id: int) -> bool:
        """
        Clear block state for account (when unblocked).

        Args:
            account_id: Trading account ID

        Returns:
            True if cleared successfully
        """
        return self.write_block_state(
            account_id=account_id,
            blocked=False,
            block_type=None,
            blocked_at=None,
            expires_at=None,
            triggered_by=[],
            reasons=[],
        )


class BlockStateSync:
    """
    Synchronizes BlockState with MT5 EA.

    Reads from database and writes to EA communication files.
    """

    def __init__(self, db_session: Any, ea_layer: EACommunicationLayer | None = None):
        """
        Initialize block state sync.

        Args:
            db_session: Database session
            ea_layer: EA communication layer (creates default if None)
        """
        self._db = db_session
        self._repo = BlockRepository(db_session)
        self._ea_layer = ea_layer or EACommunicationLayer()

    def sync_account(self, account_id: int) -> dict:
        """
        Sync block state for one account to EA file.

        Args:
            account_id: Trading account ID

        Returns:
            Dict with sync result
        """
        block = self._repo.get_active_block(account_id)

        if block is None or not block.is_active():
            # No active block - clear file
            success = self._ea_layer.clear_block_state(account_id)
            return {
                "account_id": account_id,
                "synced": success,
                "blocked": False,
                "block_type": None,
            }

        # Write block state to file
        success = self._ea_layer.write_block_state(
            account_id=account_id,
            blocked=True,
            block_type=block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
            blocked_at=block.blocked_at,
            expires_at=block.expires_at,
            triggered_by=block.triggered_by or [],
            reasons=block.payload.get("reasons", []) if block.payload else [],
        )

        return {
            "account_id": account_id,
            "synced": success,
            "blocked": True,
            "block_type": block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
            "expires_at": block.expires_at.isoformat() if block.expires_at else None,
        }

    def sync_all_active(self) -> dict:
        """
        Sync all active blocks to EA files.

        Returns:
            Dict with sync results for all accounts
        """
        active_blocks = self._repo.get_active_blocks()

        results = {
            "synced_at": datetime.now(timezone.utc).isoformat(),
            "total_blocks": len(active_blocks),
            "accounts": {},
        }

        for block in active_blocks:
            result = self.sync_account(block.account_id)
            results["accounts"][str(block.account_id)] = result

        return results


class MT5BlockEnforcer:
    """
    Coordinates MT5 trade blocking.

    Responsibilities:
    - Enforce blocks by writing to EA communication files
    - Sync block state from database to MT5
    - Monitor EA connection status

    Does NOT:
    - Evaluate rules
    - Make trade decisions
    - Access MT5 directly (delegates to Mt5TradeBlocker)
    """

    def __init__(
        self,
        db_session: Any,
        ea_layer: EACommunicationLayer | None = None,
    ):
        """
        Initialize MT5 block enforcer.

        Args:
            db_session: Database session
            ea_layer: EA communication layer (creates default if None)
        """
        self._db = db_session
        self._repo = BlockRepository(db_session)
        self._ea_layer = ea_layer or EACommunicationLayer()
        self._sync = BlockStateSync(db_session, ea_layer)

    def enforce(self, account_id: int) -> dict:
        """
        Enforce block for account.

        Reads current block state from database and writes to EA file.

        Args:
            account_id: Trading account ID

        Returns:
            Dict with enforcement result
        """
        return self._sync.sync_account(account_id)

    def enforce_all(self) -> dict:
        """
        Enforce blocks for all active accounts.

        Returns:
            Dict with enforcement results
        """
        return self._sync.sync_all_active()

    def get_ea_status(self) -> EAStatus:
        """
        Get EA connection status.

        Returns:
            EAStatus with current state
        """
        return self._ea_layer.read_ea_status()

    def clear_block(self, account_id: int) -> bool:
        """
        Clear block for account (remove from EA file).

        Args:
            account_id: Trading account ID

        Returns:
            True if cleared successfully
        """
        return self._ea_layer.clear_block_state(account_id)

    def get_block_state_for_ea(self, account_id: int) -> dict:
        """
        Get formatted block state for EA consumption.

        Args:
            account_id: Trading account ID

        Returns:
            Dict formatted for EA file
        """
        block = self._repo.get_active_block(account_id)

        if block is None or not block.is_active():
            return {
                "blocked": False,
                "block_type": None,
                "remaining_seconds": 0,
            }

        remaining = block.remaining_seconds()

        return {
            "blocked": True,
            "block_type": block.block_type.value if hasattr(block.block_type, 'value') else block.block_type,
            "blocked_at": block.blocked_at.isoformat() if block.blocked_at else None,
            "expires_at": block.expires_at.isoformat() if block.expires_at else None,
            "remaining_seconds": remaining,
            "triggered_by": block.triggered_by or [],
        }
