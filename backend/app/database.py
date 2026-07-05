from collections.abc import Generator
from pathlib import Path
import shutil

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings


class Base(DeclarativeBase):
    pass


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _sqlite_path_from_url(database_url: str) -> Path | None:
    if not database_url.startswith("sqlite:///"):
        return None
    path = Path(database_url.replace("sqlite:///", "", 1))
    if path.is_absolute():
        return path
    return BACKEND_ROOT / path


def _database_url(database_url: str) -> str:
    sqlite_path = _sqlite_path_from_url(database_url)
    if sqlite_path is None:
        return database_url
    return f"sqlite:///{sqlite_path.as_posix()}"


sqlite_path = _sqlite_path_from_url(settings.database_url)
if sqlite_path is not None:
    sqlite_path.parent.mkdir(parents=True, exist_ok=True)
    _legacy_sqlite_path = BACKEND_ROOT / "data" / "trading_desk.db"
    if sqlite_path != _legacy_sqlite_path and not sqlite_path.exists() and _legacy_sqlite_path.exists():
        shutil.copy2(_legacy_sqlite_path, sqlite_path)
        for suffix in ("-wal", "-shm"):
            legacy_sidecar = Path(f"{_legacy_sqlite_path}{suffix}")
            if legacy_sidecar.exists():
                shutil.copy2(legacy_sidecar, Path(f"{sqlite_path}{suffix}"))

database_url = _database_url(settings.database_url)
engine = create_engine(
    database_url,
    connect_args={"check_same_thread": False}
    if database_url.startswith("sqlite")
    else {},
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


def get_database_url() -> str:
    return database_url


def init_db() -> None:
    from app import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
    _run_sqlite_dev_migrations()


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _run_sqlite_dev_migrations() -> None:
    if not database_url.startswith("sqlite"):
        return

    inspector = inspect(engine)
    if "trading_accounts" not in inspector.get_table_names():
        return

    account_columns = {
        column["name"] for column in inspector.get_columns("trading_accounts")
    }
    statements = []

    if "timezone" not in account_columns:
        statements.append(
            "ALTER TABLE trading_accounts "
            "ADD COLUMN timezone VARCHAR(64) NOT NULL DEFAULT 'UTC'"
        )
    if "is_active" not in account_columns:
        statements.append(
            "ALTER TABLE trading_accounts "
            "ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT 1"
        )
    if "updated_at" not in account_columns:
        statements.append("ALTER TABLE trading_accounts ADD COLUMN updated_at DATETIME")

    if "trade_journals" in inspector.get_table_names():
        journal_columns = {
            column["name"] for column in inspector.get_columns("trade_journals")
        }
        if "review_status" not in journal_columns:
            statements.append(
                "ALTER TABLE trade_journals "
                "ADD COLUMN review_status VARCHAR(40) NOT NULL DEFAULT 'pending'"
            )

    if "normalized_trades" in inspector.get_table_names():
        trade_columns = {
            column["name"] for column in inspector.get_columns("normalized_trades")
        }
        normalized_trade_columns = {
            "side": "VARCHAR(8)",
            "open_time": "DATETIME",
            "close_time": "DATETIME",
            "open_price": "FLOAT",
            "close_price": "FLOAT",
            "profit": "FLOAT",
            "net_profit": "FLOAT",
            "duration_seconds": "INTEGER",
            "entry_reason": "VARCHAR(255)",
            "exit_reason": "VARCHAR(255)",
        }
        for column_name, column_type in normalized_trade_columns.items():
            if column_name not in trade_columns:
                statements.append(
                    "ALTER TABLE normalized_trades "
                    f"ADD COLUMN {column_name} {column_type}"
                )

    if "licenses" in inspector.get_table_names():
        license_columns = {
            column["name"] for column in inspector.get_columns("licenses")
        }
        license_additions = {
            "provider": "VARCHAR(32) NOT NULL DEFAULT 'offline'",
            "owner_email": "VARCHAR(255)",
            "device_id": "VARCHAR(255)",
            "expires_at": "DATETIME",
            "last_validated_at": "DATETIME",
        }
        for column_name, column_type in license_additions.items():
            if column_name not in license_columns:
                statements.append(
                    "ALTER TABLE licenses "
                    f"ADD COLUMN {column_name} {column_type}"
                )

    if not statements:
        return

    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))

