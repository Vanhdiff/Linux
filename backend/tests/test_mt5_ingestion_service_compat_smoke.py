"""Smoke test for legacy MT5 ingestion service import compatibility.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_mt5_ingestion_service_compat_smoke.py
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.services.import_service import Mt5IngestionService as CanonicalMt5IngestionService
from app.services.ingestion_service import Mt5IngestionService as LegacyMt5IngestionService


def test_legacy_ingestion_service_import_points_to_canonical_class() -> None:
    assert LegacyMt5IngestionService is CanonicalMt5IngestionService


if __name__ == "__main__":
    test_legacy_ingestion_service_import_points_to_canonical_class()
    print("test_mt5_ingestion_service_compat_smoke: PASS")
