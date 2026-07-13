"""
MT5 Protection - File-based communication with MT5 EA.

Creates:
- MT5BlockEnforcer: Coordinates blocking enforcement
- EACommunicationLayer: File-based IPC with MT5 EA
- BlockStateSync: Synchronizes BlockState with MT5

Communication via shared files:
- block_{account_id}.json: Current block state
- ea_status.json: EA connection status
- ea_config.json: Backend-managed EA runtime configuration
- ea_command.json: Backend-managed one-shot EA command
"""
import json
import logging
import os
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.infrastructure.persistence.block_repository import BlockRepository

logger = logging.getLogger(__name__)


def default_mt5_common_files_dir() -> Path:
    """Return the MT5 FILE_COMMON directory used by the EA."""
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    return Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal" / "Common" / "Files"


MT5_DATA_DIR = default_mt5_common_files_dir()
EA_HEARTBEAT_STALE_SECONDS = 15
BACKEND_TIMING_AUDIT_FILENAME = "backend_mt5_demo_audit.jsonl"
EA_TIMING_AUDIT_FILENAME = "ea_mt5_demo_audit.jsonl"
EA_CONFIG_FILENAME = "ea_config.json"
EA_COMMAND_FILENAME = "ea_command.json"
DEFAULT_MT5_BACKEND_BASE_URL = "http://127.0.0.1:8000"


@dataclass
class EAStatus:
    """Status of the MT5 EA connection."""
    connected: bool = False
    last_heartbeat: datetime | None = None
    version: str = ""
    account_id: int | None = None
    error: str = ""
    stale: bool = False


@dataclass
class BlockFilePayload:
    """Block state file format for EA communication."""
    account_id: int
    blocked: bool
    block_type: str | None  # "temporary" or "full_day"
    blocked_at: str | None
    expires_at: str | None
    remaining_seconds: int = 0
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    triggered_by: list[str] = field(default_factory=list)
    reasons: list[dict] = field(default_factory=list)


@dataclass
class EAConfigPayload:
    """Backend-managed EA configuration contract."""
    contract_version: str = "td_ea_config.v1"
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    backend_base_url: str = DEFAULT_MT5_BACKEND_BASE_URL
    account_id: int | None = None
    timeout_ms: int = 750
    heartbeat_interval_ms: int = 1000
    enforcement_timer_ms: int = 20
    enforcement_throttle_ms: int = 10
    close_positions_when_blocked: bool = True
    delete_pending_orders_when_blocked: bool = True
    status_file_name: str = "ea_status.json"
    audit_file_name: str = EA_TIMING_AUDIT_FILENAME


@dataclass
class EACommandPayload:
    """Backend-managed one-shot EA command contract."""
    command_id: str
    command_type: str
    requested_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    account_id: int | None = None
    payload: dict[str, Any] = field(default_factory=dict)
    status: str = "pending"


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

    @property
    def data_dir(self) -> Path:
        return self._data_dir

    def _block_file_path(self, account_id: int) -> Path:
        """Get path to block state file for account."""
        return self._data_dir / f"block_{account_id}.json"

    def _status_file_path(self) -> Path:
        """Get path to EA status file."""
        return self._data_dir / "ea_status.json"

    def _backend_audit_file_path(self) -> Path:
        return self._data_dir / BACKEND_TIMING_AUDIT_FILENAME

    def _ea_audit_file_path(self) -> Path:
        return self._data_dir / EA_TIMING_AUDIT_FILENAME

    def _config_file_path(self) -> Path:
        return self._data_dir / EA_CONFIG_FILENAME

    def _command_file_path(self) -> Path:
        return self._data_dir / EA_COMMAND_FILENAME

    def diagnostics(self, account_id: int | None = None) -> dict[str, Any]:
        """Return filesystem diagnostics for backend <-> EA file sync."""
        status_path = self._status_file_path()
        status_exists = status_path.exists()
        last_modified = None
        if status_exists:
            last_modified = datetime.fromtimestamp(
                status_path.stat().st_mtime,
                tz=timezone.utc,
            ).isoformat()

        status = self.read_ea_status()
        heartbeat_age_seconds = None
        if status.last_heartbeat is not None:
            heartbeat = status.last_heartbeat
            if heartbeat.tzinfo is None:
                heartbeat = heartbeat.replace(tzinfo=timezone.utc)
            heartbeat_age_seconds = max(
                0.0,
                (datetime.now(timezone.utc) - heartbeat).total_seconds(),
            )

        block_path = self._block_file_path(account_id) if account_id is not None else None
        config = self.read_ea_config()
        command = self.read_ea_command()
        return {
            "backend_data_directory": str(self._data_dir),
            "expected_ea_data_directory": str(default_mt5_common_files_dir()),
            "status_file_path": str(status_path),
            "status_file_exists": status_exists,
            "status_file_last_modified": last_modified,
            "heartbeat_age_seconds": heartbeat_age_seconds,
            "block_file_path": str(block_path) if block_path is not None else None,
            "block_file_exists": block_path.exists() if block_path is not None else False,
            "backend_audit_file_path": str(self._backend_audit_file_path()),
            "backend_audit_file_exists": self._backend_audit_file_path().exists(),
            "ea_audit_file_path": str(self._ea_audit_file_path()),
            "ea_audit_file_exists": self._ea_audit_file_path().exists(),
            "config_file_path": str(self._config_file_path()),
            "config_file_exists": self._config_file_path().exists(),
            "config_contract_version": config.get("contract_version") if isinstance(config, dict) else None,
            "config_account_id": config.get("account_id") if isinstance(config, dict) else None,
            "command_file_path": str(self._command_file_path()),
            "command_file_exists": self._command_file_path().exists(),
            "command_id": command.get("command_id") if isinstance(command, dict) else None,
            "command_type": command.get("command_type") if isinstance(command, dict) else None,
        }

    def build_default_ea_config(
        self,
        *,
        account_id: int | None = None,
        backend_base_url: str | None = None,
    ) -> dict[str, Any]:
        return asdict(
            EAConfigPayload(
                backend_base_url=backend_base_url or DEFAULT_MT5_BACKEND_BASE_URL,
                account_id=account_id,
            )
        )

    def write_ea_config(
        self,
        *,
        account_id: int | None = None,
        backend_base_url: str | None = None,
        updates: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        payload = self.build_default_ea_config(
            account_id=account_id,
            backend_base_url=backend_base_url,
        )
        existing = self.read_ea_config()
        if isinstance(existing, dict):
            payload.update(existing)
        payload["updated_at"] = datetime.now(timezone.utc).isoformat()
        if account_id is not None:
            payload["account_id"] = account_id
        if backend_base_url is not None:
            payload["backend_base_url"] = backend_base_url
        if updates:
            payload.update(updates)
        self._write_json_file(self._config_file_path(), payload)
        return payload

    def read_ea_config(self) -> dict[str, Any] | None:
        return self._read_json_file(self._config_file_path())

    def queue_ea_command(
        self,
        *,
        command_type: str,
        account_id: int | None = None,
        payload: dict[str, Any] | None = None,
        command_id: str | None = None,
    ) -> dict[str, Any]:
        if not command_type:
            raise ValueError("command_type is required")
        safe_command_id = command_id or f"{command_type}-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
        command_payload = asdict(
            EACommandPayload(
                command_id=safe_command_id,
                command_type=command_type,
                account_id=account_id,
                payload=payload or {},
            )
        )
        self._write_json_file(self._command_file_path(), command_payload)
        return command_payload

    def read_ea_command(self) -> dict[str, Any] | None:
        return self._read_json_file(self._command_file_path())

    def clear_ea_command(self) -> bool:
        try:
            self._command_file_path().unlink(missing_ok=True)
            return True
        except Exception as exc:
            logger.error("Failed to clear MT5 EA command file: %s", exc)
            return False

    def append_backend_timing_event(
        self,
        *,
        event_type: str,
        account_id: int,
        occurred_at: datetime | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> bool:
        return self._append_timing_event(
            path=self._backend_audit_file_path(),
            source="backend",
            event_type=event_type,
            account_id=account_id,
            occurred_at=occurred_at,
            metadata=metadata,
        )

    def read_timing_events(self, account_id: int | None = None) -> dict[str, Any]:
        return {
            "backend": self._read_timing_events_from_path(
                self._backend_audit_file_path(),
                account_id=account_id,
            ),
            "ea": self._read_timing_events_from_path(
                self._ea_audit_file_path(),
                account_id=account_id,
            ),
        }

    def _append_timing_event(
        self,
        *,
        path: Path,
        source: str,
        event_type: str,
        account_id: int,
        occurred_at: datetime | None,
        metadata: dict[str, Any] | None,
    ) -> bool:
        try:
            payload = {
                "source": source,
                "event_type": event_type,
                "account_id": account_id,
                "occurred_at": (occurred_at or datetime.now(timezone.utc)).isoformat(),
                "metadata": metadata or {},
            }
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(payload, ensure_ascii=True) + "\n")
            return True
        except Exception as exc:
            logger.error("Failed to append MT5 timing audit event: %s", exc)
            return False

    def _write_json_file(self, path: Path, payload: dict[str, Any]) -> None:
        temp_path = path.with_suffix(".tmp")
        with temp_path.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
        temp_path.replace(path)

    def _read_json_file(self, path: Path) -> dict[str, Any] | None:
        if not path.exists():
            return None
        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception as exc:
            logger.error("Failed to read MT5 EA contract file %s: %s", path, exc)
            return None
        return payload if isinstance(payload, dict) else None

    def _read_timing_events_from_path(
        self,
        path: Path,
        *,
        account_id: int | None,
    ) -> list[dict[str, Any]]:
        if not path.exists():
            return []
        events: list[dict[str, Any]] = []
        try:
            with path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    text = line.strip()
                    if not text:
                        continue
                    try:
                        payload = json.loads(text)
                    except json.JSONDecodeError:
                        continue
                    if account_id is not None and payload.get("account_id") != account_id:
                        continue
                    events.append(payload)
        except Exception as exc:
            logger.error("Failed to read MT5 timing audit events: %s", exc)
            return []
        return events

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

            stale = self._heartbeat_is_stale(last_heartbeat)
            connected = bool(data.get("connected", False)) and not stale
            error = data.get("error", "")
            if stale:
                error = "EA heartbeat is stale"

            return EAStatus(
                connected=connected,
                last_heartbeat=last_heartbeat,
                version=data.get("version", ""),
                account_id=data.get("account_id"),
                error=error,
                stale=stale,
            )
        except Exception as e:
            return EAStatus(connected=False, error=str(e))

    def _heartbeat_is_stale(self, last_heartbeat: datetime | None) -> bool:
        if last_heartbeat is None:
            return True
        heartbeat = last_heartbeat
        if heartbeat.tzinfo is None:
            heartbeat = heartbeat.replace(tzinfo=timezone.utc)
        age_seconds = (datetime.now(timezone.utc) - heartbeat).total_seconds()
        return age_seconds > EA_HEARTBEAT_STALE_SECONDS

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
