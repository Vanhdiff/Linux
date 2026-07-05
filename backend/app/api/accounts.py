from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import TradingAccount
from app.schemas.account_schema import AccountCreate, AccountRead


router = APIRouter(prefix="/accounts", tags=["accounts"])


@router.get("", response_model=list[AccountRead])
def list_accounts(db: Annotated[Session, Depends(get_db)]):
    return db.query(TradingAccount).order_by(TradingAccount.id.desc()).all()


@router.post(
    "",
    response_model=AccountRead,
    status_code=status.HTTP_201_CREATED,
)
def create_account(
    payload: AccountCreate,
    db: Annotated[Session, Depends(get_db)],
):
    existing_account = (
        db.query(TradingAccount)
        .filter(TradingAccount.login == payload.login)
        .one_or_none()
    )
    if existing_account is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Account login already exists",
        )

    account = TradingAccount(
        name=payload.name,
        broker=payload.broker,
        server=payload.server,
        login=payload.login,
        currency=payload.currency,
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


@router.get("/{account_id}", response_model=AccountRead)
def get_account(account_id: int, db: Annotated[Session, Depends(get_db)]):
    account = db.get(TradingAccount, account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="Account not found")
    return account

