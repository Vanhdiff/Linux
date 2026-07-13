from pydantic import BaseModel


class AccountBase(BaseModel):
    name: str = "Main account"
    broker: str
    server: str
    login: str
    currency: str


class AccountCreate(AccountBase):
    pass


class AccountRead(AccountBase):
    id: int
    is_active: bool = False

    model_config = {"from_attributes": True}

