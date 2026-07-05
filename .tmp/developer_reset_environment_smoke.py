import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(r"E:\Tradingapp\epp_tr-desktop")
DB_PATH = ROOT / ".tmp" / "developer_reset_environment_smoke.db"
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
if DB_PATH.exists():
    DB_PATH.unlink()
DB_PATH.touch()

sys.path.insert(0, str(ROOT / "backend" / ".deps"))
sys.path.insert(0, str(ROOT / "backend"))
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.models import (  # noqa: E402
    AccountSnapshot,
    DailyAnalytics,
    EconomicEvent,
    GuardrailSetting,
    NormalizedTrade,
    RawDeal,
    RawMt5Import,
    RuleBreak,
    TradeJournal,
    TradingAccount,
)
from app.services.developer_reset_service import DeveloperResetService  # noqa: E402


Base.metadata.create_all(bind=engine)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


class FakeMt5ResetService:
    def market_snapshot(self, **kwargs):
        now = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
        date_from = kwargs.get("date_from") or now - timedelta(days=30)
        date_to = kwargs.get("date_to") or now
        return {
            "account_info": {
                "login": "RESET-001",
                "name": "Reset Account",
                "company": "Pepperstone",
                "server": "Demo",
                "currency": "USD",
                "balance": 50123.45,
                "equity": 50123.45,
                "margin": 0,
                "free_margin": 50123.45,
                "profit": 0,
            },
            "positions": [],
            "orders": [],
            "deals": [
                {
                    "external_deal_id": "deal-open-1",
                    "external_order_id": "order-1",
                    "symbol": "EURUSD",
                    "direction": "buy",
                    "entry_type": "in",
                    "volume": 1.0,
                    "price": 1.1,
                    "profit": 0,
                    "commission": -3.5,
                    "swap": 0,
                    "time": (now - timedelta(minutes=5)).isoformat(),
                    "comment": "open",
                    "position_id": "position-1",
                },
                {
                    "external_deal_id": "deal-close-1",
                    "external_order_id": "order-1",
                    "symbol": "EURUSD",
                    "direction": "sell",
                    "entry_type": "out",
                    "volume": 1.0,
                    "price": 1.101,
                    "profit": 50,
                    "commission": -3.5,
                    "swap": 0,
                    "time": (now - timedelta(minutes=1)).isoformat(),
                    "comment": "close",
                    "position_id": "position-1",
                },
            ],
            "date_from": date_from,
            "date_to": date_to,
        }


with SessionLocal() as db:
    account = TradingAccount(
        name="Old Account",
        broker="Old Broker",
        server="Old Server",
        login="RESET-001",
        currency="USD",
        is_active=True,
    )
    db.add(account)
    db.flush()
    db.add(
        GuardrailSetting(
            account_id=account.id,
            max_daily_loss=1000,
            max_trades_per_day=2,
            max_risk_per_trade=300,
            block_high_impact_news=True,
            enabled=True,
            settings={"trade_blocking_enabled": True},
        )
    )
    db.add(AccountSnapshot(account_id=account.id, captured_at=datetime.utcnow(), balance=100, equity=100, margin=0, free_margin=100, margin_level=None, profit=0, raw_payload={}))
    db.add(RawMt5Import(account_id=account.id, import_type="deals", payload={}))
    db.add(RawDeal(account_id=account.id, external_deal_id="old-deal", symbol="XAUUSD", direction="buy", entry_type="in", volume=1.0, price=2300, profit=0, commission=0, swap=0, deal_time=datetime.utcnow(), comment="old", raw_payload={}))
    trade = NormalizedTrade(account_id=account.id, symbol="XAUUSD", direction="buy", side="buy", volume=1.0, opened_at=datetime.utcnow(), open_time=datetime.utcnow(), closed_at=datetime.utcnow(), close_time=datetime.utcnow(), entry_price=2300, open_price=2300, exit_price=2290, close_price=2290, stop_loss=2290, take_profit=None, commission=0, swap=0, gross_pnl=-100, profit=-100, net_pnl=-100, net_profit=-100, duration_seconds=60, entry_reason="old", exit_reason="old", risk_amount=100, r_multiple=-1, setup_tag="old", session="asia", status="closed", source_deal_ids=["old-deal"])
    db.add(trade)
    db.flush()
    db.add(TradeJournal(trade_id=trade.id, notes="old journal", review_status="pending"))
    db.add(DailyAnalytics(account_id=account.id, trade_date=datetime.utcnow().date(), net_pnl=-100, gross_pnl=-100, trade_count=1, win_count=0, loss_count=1, win_rate=0, profit_factor=0, max_drawdown=100, avg_r=-1, risk_total=100, metrics={}))
    db.add(RuleBreak(account_id=account.id, trade_id=trade.id, rule_code="old_rule", severity="warning", message="old", payload={}))
    db.add(EconomicEvent(source="ff", external_event_id="evt-1", event_time=datetime.utcnow(), currency="USD", impact="high", title="NFP", actual=None, forecast=None, previous=None, raw_payload={}))
    db.commit()

    result = DeveloperResetService(db, mt5_service=FakeMt5ResetService()).reset_environment(history_days=120)
    db.expire_all()

    require(result["guardrails_preserved"] is True, result)
    require(result["account"]["login"] == "RESET-001", result)
    require(result["reset"]["deleted"]["normalized_trades"] == 1, result)
    require(result["reset"]["deleted"]["trade_journals"] == 1, result)
    require(result["reset"]["deleted"]["daily_analytics"] == 1, result)
    require(result["reset"]["deleted"]["rule_breaks"] == 1, result)
    require(result["reset"]["deleted"]["economic_events"] == 1, result)
    require(db.query(GuardrailSetting).count() == 1, "guardrail settings should be preserved")
    require(db.query(AccountSnapshot).count() == 1, "fresh account snapshot should exist")
    require(db.query(RawDeal).count() == 2, "re-imported raw deals should exist")
    require(db.query(NormalizedTrade).count() == 1, "re-normalized trade should exist")
    fresh_snapshot = db.query(AccountSnapshot).order_by(AccountSnapshot.id.desc()).first()
    require(round(fresh_snapshot.balance, 2) == 50123.45, fresh_snapshot.balance)

print("developer reset environment smoke: PASS")
