from collections import Counter, defaultdict
from datetime import date, datetime

from sqlalchemy.orm import Session

from app.models import AccountSnapshot, NormalizedTrade, TradeJournal, TradingAccount


class AnalyticsService:
    def __init__(self, db: Session) -> None:
        self._db = db

    def overview(self, account_id: int | None = None) -> dict:
        trades = self._closed_trades(account_id)
        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]
        breakevens = [trade for trade in trades if trade.net_pnl == 0]
        net_pnl = round(sum(trade.net_pnl for trade in trades), 2)
        gross_pnl = round(sum(trade.gross_pnl for trade in trades), 2)
        r_values = [trade.r_multiple for trade in trades if trade.r_multiple is not None]

        return {
            "status": "ready",
            "source": "normalized_trades",
            "account_id": account_id,
            "account": self._account_summary(account_id),
            "latest_snapshot": self._snapshot_summary(self._latest_snapshot(account_id)),
            "trade_count": len(trades),
            "win_count": len(wins),
            "loss_count": len(losses),
            "breakeven_count": len(breakevens),
            "win_rate": self._percent(len(wins), len(trades)),
            "gross_pnl": gross_pnl,
            "net_pnl": net_pnl,
            "profit_factor": self._profit_factor(trades),
            "expectancy": self._expectancy(trades),
            "average_r": round(sum(r_values) / len(r_values), 4) if r_values else None,
            "max_drawdown": self.max_drawdown(account_id)["max_drawdown"],
            "daily_pnl": self.pnl_by_day(account_id),
            "weekly_pnl": self.pnl_by_week(account_id),
            "monthly_pnl": self.pnl_by_month(account_id),
            "symbols": self.symbols(account_id),
            "sessions": self.sessions(account_id),
            "setups": self.setups(account_id),
            "mistake_frequency": self.mistake_frequency(account_id),
        }

    def pnl_by_day(self, account_id: int | None = None) -> list[dict]:
        return self._pnl_by_period(account_id, period="day")

    def pnl_by_week(self, account_id: int | None = None) -> list[dict]:
        return self._pnl_by_period(account_id, period="week")

    def pnl_by_month(self, account_id: int | None = None) -> list[dict]:
        return self._pnl_by_period(account_id, period="month")

    def max_drawdown(self, account_id: int | None = None) -> dict:
        equity = 0.0
        peak = 0.0
        max_drawdown = 0.0
        curve = []

        for trade in self._closed_trades(account_id):
            equity = round(equity + trade.net_pnl, 2)
            peak = max(peak, equity)
            drawdown = round(equity - peak, 2)
            max_drawdown = min(max_drawdown, drawdown)
            curve.append(
                {
                    "trade_id": trade.id,
                    "closed_at": trade.closed_at.isoformat()
                    if trade.closed_at is not None
                    else None,
                    "net_pnl": trade.net_pnl,
                    "risk_amount": trade.risk_amount,
                    "r_multiple": trade.r_multiple,
                    "equity": equity,
                    "peak": round(peak, 2),
                    "drawdown": drawdown,
                }
            )

        return {
            "account_id": account_id,
            "max_drawdown": round(abs(max_drawdown), 2),
            "curve": curve,
        }

    def symbols(self, account_id: int | None = None) -> list[dict]:
        return self._group_performance(
            self._closed_trades(account_id),
            key_fn=lambda trade: trade.symbol or "Unknown",
            name_key="symbol",
        )

    def sessions(self, account_id: int | None = None) -> list[dict]:
        return self._group_performance(
            self._closed_trades(account_id),
            key_fn=lambda trade: trade.session or "Unknown",
            name_key="session",
        )

    def setups(self, account_id: int | None = None) -> list[dict]:
        return self._group_performance(
            self._closed_trades(account_id),
            key_fn=self._setup_name,
            name_key="setup",
        )

    def mistake_frequency(self, account_id: int | None = None) -> list[dict]:
        query = self._db.query(TradeJournal).join(NormalizedTrade)
        if account_id is not None:
            query = query.filter(NormalizedTrade.account_id == account_id)

        counter: Counter[str] = Counter()
        for journal in query.all():
            for mistake in journal.mistakes or []:
                if mistake:
                    counter[mistake] += 1

        return [
            {"mistake": mistake, "count": count}
            for mistake, count in counter.most_common()
        ]

    def _pnl_by_period(self, account_id: int | None, period: str) -> list[dict]:
        grouped: dict[str, list[NormalizedTrade]] = defaultdict(list)
        for trade in self._closed_trades(account_id):
            if trade.closed_at is None:
                continue
            grouped[self._period_key(trade.closed_at, period)].append(trade)

        return [
            self._period_summary(period_key, trades)
            for period_key, trades in sorted(grouped.items())
        ]

    def _period_key(self, value: datetime, period: str) -> str:
        if period == "week":
            year, week, _ = value.isocalendar()
            return f"{year}-W{week:02d}"
        if period == "month":
            return value.strftime("%Y-%m")
        return value.date().isoformat()

    def _period_summary(self, period_key: str, trades: list[NormalizedTrade]) -> dict:
        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]
        r_values = [trade.r_multiple for trade in trades if trade.r_multiple is not None]
        return {
            "period": period_key,
            "trade_count": len(trades),
            "win_count": len(wins),
            "loss_count": len(losses),
            "win_rate": self._percent(len(wins), len(trades)),
            "gross_pnl": round(sum(trade.gross_pnl for trade in trades), 2),
            "net_pnl": round(sum(trade.net_pnl for trade in trades), 2),
            "profit_factor": self._profit_factor(trades),
            "expectancy": self._expectancy(trades),
            "average_r": round(sum(r_values) / len(r_values), 4) if r_values else None,
        }

    def _group_performance(
        self,
        trades: list[NormalizedTrade],
        key_fn,
        name_key: str,
    ) -> list[dict]:
        grouped: dict[str, list[NormalizedTrade]] = defaultdict(list)
        for trade in trades:
            grouped[key_fn(trade)].append(trade)

        rows = []
        for name, group_trades in sorted(grouped.items()):
            wins = [trade for trade in group_trades if trade.net_pnl > 0]
            r_values = [
                trade.r_multiple
                for trade in group_trades
                if trade.r_multiple is not None
            ]
            rows.append(
                {
                    name_key: name,
                    "trade_count": len(group_trades),
                    "win_count": len(wins),
                    "loss_count": len(
                        [trade for trade in group_trades if trade.net_pnl < 0]
                    ),
                    "win_rate": self._percent(len(wins), len(group_trades)),
                    "gross_pnl": round(
                        sum(trade.gross_pnl for trade in group_trades),
                        2,
                    ),
                    "net_pnl": round(sum(trade.net_pnl for trade in group_trades), 2),
                    "profit_factor": self._profit_factor(group_trades),
                    "expectancy": self._expectancy(group_trades),
                    "average_r": round(sum(r_values) / len(r_values), 4)
                    if r_values
                    else None,
                }
            )
        return rows

    def _closed_trades(self, account_id: int | None) -> list[NormalizedTrade]:
        query = self._db.query(NormalizedTrade).filter(
            NormalizedTrade.status.in_(["closed", "breakeven"])
        )
        if account_id is not None:
            query = query.filter(NormalizedTrade.account_id == account_id)
        return query.order_by(NormalizedTrade.closed_at.asc(), NormalizedTrade.id.asc()).all()

    def _account_summary(self, account_id: int | None) -> dict | None:
        if account_id is None:
            return None
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            return None
        return {
            "id": account.id,
            "name": account.name,
            "broker": account.broker,
            "server": account.server,
            "login": account.login,
            "currency": account.currency,
        }

    def _latest_snapshot(self, account_id: int | None) -> AccountSnapshot | None:
        query = self._db.query(AccountSnapshot)
        if account_id is not None:
            query = query.filter(AccountSnapshot.account_id == account_id)
        return query.order_by(AccountSnapshot.captured_at.desc()).first()

    def _snapshot_summary(self, snapshot: AccountSnapshot | None) -> dict | None:
        if snapshot is None:
            return None
        return {
            "captured_at": snapshot.captured_at.isoformat(),
            "balance": snapshot.balance,
            "equity": snapshot.equity,
            "margin": snapshot.margin,
            "free_margin": snapshot.free_margin,
            "margin_level": snapshot.margin_level,
            "floating_profit": snapshot.profit,
        }

    def _setup_name(self, trade: NormalizedTrade) -> str:
        if trade.journal is not None and trade.journal.setup:
            return trade.journal.setup
        return trade.setup_tag or "Unlabeled"

    def _profit_factor(self, trades: list[NormalizedTrade]) -> float | None:
        gross_profit = sum(trade.net_pnl for trade in trades if trade.net_pnl > 0)
        gross_loss = abs(sum(trade.net_pnl for trade in trades if trade.net_pnl < 0))
        if gross_loss == 0:
            return None
        return round(gross_profit / gross_loss, 4)

    def _expectancy(self, trades: list[NormalizedTrade]) -> float:
        if not trades:
            return 0.0
        return round(sum(trade.net_pnl for trade in trades) / len(trades), 2)

    def _percent(self, numerator: int, denominator: int) -> float:
        if denominator == 0:
            return 0.0
        return round((numerator / denominator) * 100, 2)

