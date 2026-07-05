from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import NotebookNote
from app.schemas.notebook import (
    NotebookNotePatch,
    NotebookNoteRead,
    NotebookNoteWrite,
)


router = APIRouter(prefix="/notebook", tags=["notebook"])


@router.get("/notes", response_model=list[NotebookNoteRead])
def list_notes(
    db: Annotated[Session, Depends(get_db)],
    account_id: Annotated[int | None, Query(ge=1)] = None,
):
    query = db.query(NotebookNote)
    if account_id is not None:
        query = query.filter(
            (NotebookNote.account_id == account_id)
            | (NotebookNote.account_id.is_(None))
        )
    return query.order_by(
        NotebookNote.pinned.desc(),
        NotebookNote.updated_at.desc(),
        NotebookNote.id.desc(),
    ).all()


@router.post(
    "/notes",
    response_model=NotebookNoteRead,
    status_code=status.HTTP_201_CREATED,
)
def create_note(
    payload: NotebookNoteWrite,
    db: Annotated[Session, Depends(get_db)],
):
    note = NotebookNote(**payload.model_dump(mode="json"))
    db.add(note)
    db.commit()
    db.refresh(note)
    return note


@router.patch("/notes/{note_id}", response_model=NotebookNoteRead)
def patch_note(
    note_id: int,
    payload: NotebookNotePatch,
    db: Annotated[Session, Depends(get_db)],
):
    note = db.get(NotebookNote, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Notebook note not found")

    for key, value in payload.model_dump(
        exclude_unset=True,
        mode="json",
    ).items():
        setattr(note, key, value)

    db.commit()
    db.refresh(note)
    return note


@router.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, db: Annotated[Session, Depends(get_db)]):
    note = db.get(NotebookNote, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Notebook note not found")

    db.delete(note)
    db.commit()
