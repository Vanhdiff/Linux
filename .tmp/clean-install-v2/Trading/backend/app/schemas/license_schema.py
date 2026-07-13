from datetime import datetime

from pydantic import BaseModel


class LicenseCreate(BaseModel):
    license_key: str


class LicenseRead(BaseModel):
    license_key: str | None = None
    provider: str | None = None
    owner_email: str | None = None
    device_id: str | None = None
    is_active: bool = False
    activated_at: datetime | None = None
    expires_at: datetime | None = None
    last_validated_at: datetime | None = None
    message: str

    model_config = {"from_attributes": True}


class LicenseSessionCreate(BaseModel):
    license_key: str
    owner_email: str | None = None
    device_id: str
    expires_at: datetime | None = None
    provider: str = "supabase"
