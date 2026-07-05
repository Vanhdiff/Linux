from functools import lru_cache
from pathlib import Path
import os

from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _default_database_url() -> str:
    configured = os.environ.get("DATABASE_URL")
    if configured:
        return configured

    if os.name == "nt":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            path = Path(local_app_data) / "TradingDesk" / "data" / "trading_desk.db"
            return f"sqlite:///{path.as_posix()}"

    path = BACKEND_ROOT / "data" / "trading_desk.db"
    return f"sqlite:///{path.as_posix()}"


class Settings(BaseSettings):
    app_name: str = "Trading Desk API"
    app_env: str = "development"
    api_prefix: str = "/api"
    license_mode: str = "offline"
    database_url: str = _default_database_url()
    ai_coach_enabled: bool = False
    ai_provider: str = "openai"
    ai_api_key: str | None = None
    ai_model: str = "gpt-4o-mini"
    ai_base_url: str = "https://api.openai.com/v1"
    ai_timeout_seconds: int = 25
    cors_origins: list[str] = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ]

    model_config = SettingsConfigDict(
        env_file=BACKEND_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

