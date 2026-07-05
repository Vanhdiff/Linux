from datetime import datetime

from pydantic import BaseModel, Field


class NotebookTask(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    done: bool = False


class NotebookNoteWrite(BaseModel):
    account_id: int | None = Field(default=None, ge=1)
    title: str = Field(min_length=1, max_length=180)
    template: str = Field(default="Blank Note", max_length=120)
    plan: str = ""
    note: str = ""
    pinned: bool = False
    saved: bool = True
    icon_key: str = Field(default="edit_note", max_length=80)
    accent_key: str = Field(default="primary", max_length=80)
    tasks: list[NotebookTask] = Field(default_factory=list)


class NotebookNotePatch(BaseModel):
    account_id: int | None = Field(default=None, ge=1)
    title: str | None = Field(default=None, min_length=1, max_length=180)
    template: str | None = Field(default=None, max_length=120)
    plan: str | None = None
    note: str | None = None
    pinned: bool | None = None
    saved: bool | None = None
    icon_key: str | None = Field(default=None, max_length=80)
    accent_key: str | None = Field(default=None, max_length=80)
    tasks: list[NotebookTask] | None = None


class NotebookNoteRead(BaseModel):
    id: int
    account_id: int | None = None
    title: str
    template: str
    plan: str
    note: str
    pinned: bool
    saved: bool
    icon_key: str
    accent_key: str
    tasks: list[NotebookTask]
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
