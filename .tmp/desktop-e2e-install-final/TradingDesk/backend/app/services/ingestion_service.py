"""Backward-compatible import path for the MT5 ingestion service.

The canonical implementation lives in ``app.services.import_service``.
Keep this shim while legacy imports are being phased out so the codebase
has a single source of truth without breaking older modules.
"""

from app.services.import_service import Mt5IngestionService

__all__ = ["Mt5IngestionService"]
