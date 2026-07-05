import asyncio
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.config import settings
from app.models import License
from app.schemas.license_schema import (
    LicenseCreate,
    LicenseRead,
    LicenseSessionCreate,
)
from app.services.mt5_trade_blocker import Mt5TradeBlocker

router = APIRouter(prefix="/license", tags=["license"])

OFFLINE_LICENSE_PREFIX = "OFFLINE-"


def _validate_license_key(key: str) -> bool:
    return key.startswith(OFFLINE_LICENSE_PREFIX) and len(key) == 20


def get_current_license(db: Session) -> License | None:
    return db.query(License).order_by(License.id.desc()).first()


def _is_online_session_valid(license_record: License) -> bool:
    if not license_record.is_active:
        return False
    if license_record.provider != "supabase":
        return True
    if license_record.expires_at is None:
        return False
    expires_at = license_record.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at > datetime.now(timezone.utc)


def is_license_active(db: Session) -> bool:
    license_record = get_current_license(db)
    return bool(license_record and _is_online_session_valid(license_record))


def _ensure_trade_blocker_running(request: Request) -> None:
    task = getattr(request.app.state, "mt5_trade_blocker_task", None)
    if task is not None and not task.done():
        return
    blocker = Mt5TradeBlocker(poll_seconds=0.10)
    request.app.state.mt5_trade_blocker = blocker
    request.app.state.mt5_trade_blocker_task = asyncio.create_task(
        blocker.run_forever()
    )


def _stop_trade_blocker(request: Request) -> None:
    task = getattr(request.app.state, "mt5_trade_blocker_task", None)
    if task is not None and not task.done():
        task.cancel()
    request.app.state.mt5_trade_blocker_task = None
    request.app.state.mt5_trade_blocker = None


def _build_license_read(license_record: License | None) -> LicenseRead:
    if license_record is None:
        return LicenseRead(
            license_key=None,
            provider=None,
            owner_email=None,
            device_id=None,
            is_active=False,
            activated_at=None,
            expires_at=None,
            last_validated_at=None,
            message="No license installed",
        )

    is_active = _is_online_session_valid(license_record)
    if license_record.provider == "supabase" and license_record.is_active and not is_active:
        message = "License session expired"
    else:
        message = "License active" if is_active else "License not active"

    return LicenseRead(
        license_key=license_record.license_key,
        provider=license_record.provider,
        owner_email=license_record.owner_email,
        device_id=license_record.device_id,
        is_active=is_active,
        activated_at=license_record.activated_at,
        expires_at=license_record.expires_at,
        last_validated_at=license_record.last_validated_at,
        message=message,
    )


@router.get("", response_model=LicenseRead)
def get_license(db: Annotated[Session, Depends(get_db)]):
    return _build_license_read(get_current_license(db))


@router.post("", response_model=LicenseRead, status_code=status.HTTP_201_CREATED)
async def activate_license(
    payload: LicenseCreate,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
):
    if settings.license_mode == "supabase":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Offline activation is disabled in Supabase license mode",
        )

    if not _validate_license_key(payload.license_key):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid license key format",
        )

    license_record = db.query(License).first()
    if license_record is None:
        license_record = License(license_key=payload.license_key)
        db.add(license_record)
    else:
        license_record.license_key = payload.license_key

    license_record.provider = "offline"
    license_record.owner_email = None
    license_record.device_id = None
    license_record.is_active = True
    license_record.activated_at = datetime.utcnow()
    license_record.expires_at = None
    license_record.last_validated_at = datetime.utcnow()
    db.commit()
    db.refresh(license_record)

    license_view = _build_license_read(license_record)
    _ensure_trade_blocker_running(request)
    return license_view.model_copy(
        update={"message": "License activated successfully"},
    )


@router.post("/session", response_model=LicenseRead)
async def upsert_online_license_session(
    payload: LicenseSessionCreate,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
):
    if payload.expires_at is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="expires_at is required for online license sessions",
        )

    license_record = get_current_license(db)
    if license_record is None:
        license_record = License(license_key=payload.license_key)
        db.add(license_record)
    else:
        license_record.license_key = payload.license_key

    license_record.provider = payload.provider
    license_record.owner_email = payload.owner_email
    license_record.device_id = payload.device_id
    license_record.is_active = True
    license_record.activated_at = datetime.utcnow()
    license_record.expires_at = payload.expires_at
    license_record.last_validated_at = datetime.utcnow()
    db.commit()
    db.refresh(license_record)

    license_view = _build_license_read(license_record)
    _ensure_trade_blocker_running(request)
    return license_view.model_copy(
        update={"message": "Online license session granted"},
    )


@router.delete("/session", response_model=LicenseRead)
async def clear_online_license_session(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
):
    license_record = get_current_license(db)
    if license_record is None:
        _stop_trade_blocker(request)
        return _build_license_read(None)

    license_record.is_active = False
    license_record.expires_at = None
    license_record.last_validated_at = datetime.utcnow()
    db.commit()
    db.refresh(license_record)
    _stop_trade_blocker(request)
    return _build_license_read(license_record)
