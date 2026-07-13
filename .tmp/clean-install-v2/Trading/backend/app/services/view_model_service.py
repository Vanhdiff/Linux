import calendar
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import (
    AccountSnapshot,
    GuardrailSetting,
    NormalizedTrade,
    RuleBreak,
    TradingAccount,
)
from app.services.analytics_service import AnalyticsService


class ViewModelService:
    def __init__(self, db: Session) -> None:
        self._db = db
        self._analytics = AnalyticsService(db)

    def dashboard(self, account_id: int | None = None, period: str = "day") -> dict:
        period_start = self._period_start(account_id, period)
        trades = self._closed_trades(account_id, start_date=period_start)
        today_trades = self._closed_trades(
            account_id,
            start_date=self._today(),
            end_date=self._today(),
        )
        recent_trades = sorted(
            trades,
            key=lambda trade: (trade.closed_at or trade.opened_at, trade.id),
            reverse=True,
        )[:10]
        drawdown = self._drawdown_summary(account_id, trades)

        return {
            "account_id": account_id,
            "period": period,
            "account": self._account_summary(account_id),
            "latest_snapshot": self._latest_snapshot_summary(account_id),
            "guardrail_settings": self._guardrail_settings_summary(account_id),
            "analytics": self._dashboard_analytics(account_id, trades, today_trades, drawdown),
            "drawdown": drawdown,
            "recent_trades": [self._trade_summary(trade) for trade in recent_trades],
        }

    def journal_calendar(self, account_id: int | None, month: str) -> dict:
        start, end = self._month_bounds(month)
        trades = self._closed_trades(account_id, start_date=start, end_date=end)
        grouped = self._trades_by_date(trades)

        days = []
        for day in range(1, calendar.monthrange(start.year, start.month)[1] + 1):
            trade_date = date(start.year, start.month, day)
            day_trades = grouped.get(trade_date, [])
            days.append(self._journal_day_summary(trade_date, day_trades))

        return {
            "account_id": account_id,
            "month": month,
            "days": days,
            "summary": self._period_summary(trades),
        }

    def journal_day(self, account_id: int | None, trade_date: date) -> dict:
        trades = self._closed_trades(
            account_id,
            start_date=trade_date,
            end_date=trade_date,
        )
        summary = self._period_summary(trades)
        summary.update(self._journal_guardrail_summary(account_id, trade_date, trades))
        return {
            "account_id": account_id,
            "date": trade_date.isoformat(),
            "summary": summary,
            "trades": [self._trade_summary(trade, include_journal=True) for trade in trades],
        }

    def journal_month_summary(self, account_id: int | None, month: str) -> dict:
        start, end = self._month_bounds(month)
        trades = self._closed_trades(account_id, start_date=start, end_date=end)
        weekly = defaultdict(list)
        for trade in trades:
            if trade.closed_at is None:
                continue
            year, week, _ = trade.closed_at.isocalendar()
            weekly[f"{year}-W{week:02d}"].append(trade)

        return {
            "account_id": account_id,
            "month": month,
            "summary": self._period_summary(trades),
            "weekly_breakdown": [
                {"period": period, **self._period_summary(period_trades)}
                for period, period_trades in sorted(weekly.items())
            ],
            "symbols": self._group_performance(
                trades,
                key_fn=lambda trade: trade.symbol or "Unknown",
                name_key="symbol",
            ),
            "sessions": self._group_performance(
                trades,
                key_fn=lambda trade: trade.session or "Unknown",
                name_key="session",
            ),
            "setups": self._group_performance(
                trades,
                key_fn=lambda trade: (
                    trade.journal.setup
                    if trade.journal and trade.journal.setup
                    else trade.setup_tag or "Unlabeled"
                ),
                name_key="setup",
            ),
            "mistake_frequency": self._mistake_frequency(trades),
        }

    def _closed_trades(
        self,
        account_id: int | None,
        start_date: date | None = None,
        end_date: date | None = None,
    ) -> list[NormalizedTrade]:
        query = self._db.query(NormalizedTrade).filter(
            NormalizedTrade.status.in_(["closed", "breakeven"])
        )
        if account_id is not None:
            query = query.filter(NormalizedTrade.account_id == account_id)
        if start_date is not None:
            query = query.filter(NormalizedTrade.closed_at >= datetime.combine(
                start_date,
                datetime.min.time(),
            ))
        if end_date is not None:
            query = query.filter(NormalizedTrade.closed_at <= datetime.combine(
                end_date,
                datetime.max.time(),
            ))
        return query.order_by(NormalizedTrade.closed_at.asc(), NormalizedTrade.id.asc()).all()

    def _trades_by_date(
        self,
        trades: list[NormalizedTrade],
    ) -> dict[date, list[NormalizedTrade]]:
        grouped: dict[date, list[NormalizedTrade]] = defaultdict(list)
        for trade in trades:
            if trade.closed_at is not None:
                grouped[trade.closed_at.date()].append(trade)
        return grouped

    def _journal_day_summary(
        self,
        trade_date: date,
        trades: list[NormalizedTrade],
    ) -> dict:
        return {
            "date": trade_date.isoformat(),
            **self._period_summary(trades),
            "trades": [self._trade_summary(trade) for trade in trades],
        }

    def _period_summary(self, trades: list[NormalizedTrade]) -> dict:
        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]
        r_values = [trade.r_multiple for trade in trades if trade.r_multiple is not None]
        win_r_values = [value for value in r_values if value > 0]
        loss_r_values = [abs(value) for value in r_values if value < 0]
        net_pnl = sum(trade.net_pnl for trade in trades)
        gross_pnl = sum(trade.gross_pnl for trade in trades)
        avg_win = sum(trade.net_pnl for trade in wins) / len(wins) if wins else 0
        avg_loss = sum(trade.net_pnl for trade in losses) / len(losses) if losses else 0
        avg_win_r = sum(win_r_values) / len(win_r_values) if win_r_values else 0
        avg_loss_r = sum(loss_r_values) / len(loss_r_values) if loss_r_values else 0
        average_rr = avg_win_r / avg_loss_r if avg_loss_r else 0
        return {
            "trade_count": len(trades),
            "win_count": len(wins),
            "loss_count": len(losses),
            "win_rate": self._percent(len(wins), len(trades)),
            "gross_pnl": round(gross_pnl, 2),
            "net_pnl": round(net_pnl, 2),
            "avg_win": round(avg_win, 2),
            "avg_loss": round(avg_loss, 2),
            "profit_factor": self._profit_factor(trades),
            "expectancy": self._expectancy(trades),
            "average_r": round(sum(r_values) / len(r_values), 4) if r_values else None,
            "average_win_r": round(avg_win_r, 4),
            "average_loss_r": round(avg_loss_r, 4),
            "average_risk_reward": round(average_rr, 4),
            "best_r": round(max(r_values), 4) if r_values else 0,
            "worst_r": round(min(r_values), 4) if r_values else 0,
        }

    def _journal_guardrail_summary(
        self,
        account_id: int | None,
        trade_date: date,
        trades: list[NormalizedTrade],
    ) -> dict:
        settings = self._latest_guardrail_settings(account_id)
        net_pnl = round(sum(trade.net_pnl for trade in trades), 2)
        balance_base = self._latest_balance(account_id)
        day_start_balance = self._daily_start_account_value(account_id, trade_date)
        max_daily_loss = settings.max_daily_loss if settings else None
        max_trades = settings.max_trades_per_day if settings else None

        rule_break_count = self._rule_break_count(account_id, trade_date)
        daily_loss_ok = max_daily_loss is None or net_pnl > -abs(max_daily_loss)
        max_trades_ok = max_trades is None or len(trades) <= max_trades
        risk_ok = not self._has_rule_break(
            account_id,
            trade_date,
            {"risk_too_high"},
        )
        revenge_ok = not self._has_rule_break(
            account_id,
            trade_date,
            {"revenge_trading_pattern"},
        )
        checks = [daily_loss_ok, max_trades_ok, risk_ok, revenge_ok]

        return {
            "return_percent": round(net_pnl / balance_base * 100, 2)
            if balance_base
            else 0,
            "day_start_balance": round(day_start_balance, 2) if day_start_balance else 0,
            "rule_break_count": rule_break_count,
            "max_daily_loss": max_daily_loss or 0,
            "max_daily_loss_used": round(
                min(abs(net_pnl) / abs(max_daily_loss), 1),
                4,
            )
            if max_daily_loss and net_pnl < 0
            else 0,
            "discipline_score": round(
                sum(1 for passed in checks if passed) / len(checks),
                4,
            ),
        }

    def _latest_guardrail_settings(
        self,
        account_id: int | None,
    ) -> GuardrailSetting | None:
        query = self._db.query(GuardrailSetting)
        if account_id is not None:
            query = query.filter(GuardrailSetting.account_id == account_id)
        return query.order_by(GuardrailSetting.id.desc()).first()

    def _latest_balance(self, account_id: int | None) -> float:
        query = self._db.query(AccountSnapshot)
        if account_id is not None:
            query = query.filter(AccountSnapshot.account_id == account_id)
        snapshot = query.order_by(AccountSnapshot.captured_at.desc()).first()
        if snapshot is not None and snapshot.balance:
            return snapshot.balance
        return 0

    def _rule_break_count(self, account_id: int | None, trade_date: date) -> int:
        return self._rule_break_query(account_id, trade_date).count()

    def _has_rule_break(
        self,
        account_id: int | None,
        trade_date: date,
        rule_codes: set[str],
    ) -> bool:
        return (
            self._rule_break_query(account_id, trade_date)
            .filter(RuleBreak.rule_code.in_(rule_codes))
            .first()
            is not None
        )

    def _rule_break_query(self, account_id: int | None, trade_date: date):
        start = datetime.combine(trade_date, datetime.min.time())
        end = start + timedelta(days=1)
        query = self._db.query(RuleBreak).outerjoin(NormalizedTrade)
        if account_id is not None:
            query = query.filter(RuleBreak.account_id == account_id)
        return query.filter(
            (
                (NormalizedTrade.closed_at >= start)
                & (NormalizedTrade.closed_at < end)
            )
            | ((RuleBreak.detected_at >= start) & (RuleBreak.detected_at < end))
        )

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
            rows.append({name_key: name, **self._period_summary(group_trades)})
        return rows

    def _dashboard_analytics(
        self,
        account_id: int | None,
        trades: list[NormalizedTrade],
        today_trades: list[NormalizedTrade],
        drawdown: dict,
    ) -> dict:
        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]
        breakevens = [trade for trade in trades if trade.net_pnl == 0]
        net_pnl = round(sum(trade.net_pnl for trade in trades), 2)
        gross_pnl = round(sum(trade.gross_pnl for trade in trades), 2)
        r_values = [trade.r_multiple for trade in trades if trade.r_multiple is not None]
        period_summary = self._period_summary(trades)
        today_summary = self._period_summary(today_trades)

        return {
            "status": "ready",
            "source": "normalized_trades",
            "account_id": account_id,
            "account": self._account_summary(account_id),
            "latest_snapshot": self._latest_snapshot_summary(account_id),
            "trade_count": len(trades),
            "win_count": len(wins),
            "loss_count": len(losses),
            "breakeven_count": len(breakevens),
            "win_rate": self._percent(len(wins), len(trades)),
            "gross_pnl": gross_pnl,
            "net_pnl": net_pnl,
            "profit_factor": self._profit_factor(trades),
            "expectancy": self._expectancy(trades),
            "average_r": round(sum(r_values) / len(r_values), 4)
            if r_values
            else None,
            "average_win_r": period_summary["average_win_r"],
            "average_loss_r": period_summary["average_loss_r"],
            "average_risk_reward": period_summary["average_risk_reward"],
            "best_r": period_summary["best_r"],
            "worst_r": period_summary["worst_r"],
            "max_drawdown": drawdown["max_drawdown"],
            "max_drawdown_percent": drawdown["max_drawdown_percent"],
            "today": today_summary,
            "daily_pnl": self._pnl_by_period(trades, period="day"),
            "weekly_pnl": self._pnl_by_period(trades, period="week"),
            "monthly_pnl": self._pnl_by_period(trades, period="month"),
            "symbols": self._group_performance(
                trades,
                key_fn=lambda trade: trade.symbol or "Unknown",
                name_key="symbol",
            ),
            "sessions": self._group_performance(
                trades,
                key_fn=lambda trade: trade.session or "Unknown",
                name_key="session",
            ),
            "setups": self._group_performance(
                trades,
                key_fn=lambda trade: (
                    trade.journal.setup
                    if trade.journal and trade.journal.setup
                    else trade.setup_tag or "Unlabeled"
                ),
                name_key="setup",
            ),
            "mistake_frequency": self._mistake_frequency(trades),
        }

    def _drawdown_summary(
        self,
        account_id: int | None,
        trades: list[NormalizedTrade],
    ) -> dict:
        equity = 0.0
        peak = 0.0
        max_drawdown = 0.0
        curve = []

        for trade in trades:
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
            "max_drawdown_percent": round(
                abs(max_drawdown) / self._drawdown_balance_base(account_id, trades) * 100,
                4,
            )
            if self._drawdown_balance_base(account_id, trades)
            else 0,
            "curve": curve,
        }

    def _drawdown_balance_base(
        self,
        account_id: int | None,
        trades: list[NormalizedTrade],
    ) -> float:
        latest_balance = self._latest_balance(account_id)
        net_pnl = sum(trade.net_pnl for trade in trades)
        starting_balance = latest_balance - net_pnl
        if starting_balance > 0:
            return starting_balance
        return latest_balance if latest_balance > 0 else 0

    def _pnl_by_period(self, trades: list[NormalizedTrade], period: str) -> list[dict]:
        grouped: dict[str, list[NormalizedTrade]] = defaultdict(list)
        for trade in trades:
            if trade.closed_at is None:
                continue
            grouped[self._period_key(trade.closed_at, period)].append(trade)
        return [
            {"period": period_key, **self._period_summary(period_trades)}
            for period_key, period_trades in sorted(grouped.items())
        ]

    def _period_key(self, value: datetime, period: str) -> str:
        if period == "week":
            year, week, _ = value.isocalendar()
            return f"{year}-W{week:02d}"
        if period == "month":
            return value.strftime("%Y-%m")
        return value.date().isoformat()

    def _period_start(self, account_id: int | None, period: str) -> date | None:
        today = self._today()
        if period == "week":
            return today - timedelta(days=today.weekday())
        if period == "month":
            return date(today.year, today.month, 1)
        return today

    def _today(self) -> date:
        return (datetime.utcnow() + timedelta(hours=7)).date()

    def _latest_trade_closed_at(self, account_id: int | None) -> datetime | None:
        query = self._db.query(NormalizedTrade).filter(
            NormalizedTrade.status.in_(["closed", "breakeven"]),
            NormalizedTrade.closed_at.isnot(None),
        )
        if account_id is not None:
            query = query.filter(NormalizedTrade.account_id == account_id)
        trade = query.order_by(NormalizedTrade.closed_at.desc()).first()
        return trade.closed_at if trade else None

    def _mistake_frequency(self, trades: list[NormalizedTrade]) -> list[dict]:
        counter = defaultdict(int)
        for trade in trades:
            if trade.journal is None:
                continue
            for mistake in trade.journal.mistakes or []:
                if mistake:
                    counter[mistake] += 1
        return [
            {"mistake": mistake, "count": count}
            for mistake, count in sorted(
                counter.items(),
                key=lambda item: (-item[1], item[0]),
            )
        ]

    def _trade_summary(
        self,
        trade: NormalizedTrade,
        include_journal: bool = False,
    ) -> dict:
        journal = trade.journal
        payload = {
            "id": trade.id,
            "account_id": trade.account_id,
            "symbol": trade.symbol,
            "direction": trade.direction,
            "volume": trade.volume,
            "opened_at": trade.opened_at.isoformat(),
            "closed_at": trade.closed_at.isoformat() if trade.closed_at else None,
            "entry_price": trade.entry_price,
            "exit_price": trade.exit_price,
            "stop_loss": trade.stop_loss,
            "take_profit": trade.take_profit,
            "commission": trade.commission,
            "swap": trade.swap,
            "gross_pnl": trade.gross_pnl,
            "net_pnl": trade.net_pnl,
            "session": trade.session,
            "risk_amount": trade.risk_amount,
            "r_multiple": trade.r_multiple,
            "status": trade.status,
            "setup": journal.setup if journal and journal.setup else trade.setup_tag,
            "has_journal": journal is not None,
        }
        if include_journal:
            payload["journal"] = self._journal_summary(journal)
        return payload

    def _journal_summary(self, journal) -> dict | None:
        if journal is None:
            return None
        return {
            "id": journal.id,
            "setup": journal.setup,
            "mistakes": journal.mistakes,
            "emotion_before": journal.emotion_before,
            "emotion_after": journal.emotion_after,
            "followed_plan": journal.followed_plan,
            "notes": journal.notes,
            "screenshot_refs": journal.screenshot_refs,
            "review_status": journal.review_status,
            "reviewed_at": journal.reviewed_at.isoformat()
            if journal.reviewed_at
            else None,
        }

    def _account_summary(self, account_id: int | None) -> dict | None:
        if account_id is None:
            return None
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found")
        return {
            "id": account.id,
            "name": account.name,
            "broker": account.broker,
            "server": account.server,
            "login": account.login,
            "currency": account.currency,
        }

    def _latest_snapshot_summary(self, account_id: int | None) -> dict | None:
        query = self._db.query(AccountSnapshot)
        if account_id is not None:
            query = query.filter(AccountSnapshot.account_id == account_id)
        snapshot = query.order_by(AccountSnapshot.captured_at.desc()).first()
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

    def _guardrail_settings_summary(self, account_id: int | None) -> dict | None:
        settings = self._latest_guardrail_settings(account_id)
        if settings is None:
            return None
        nested = settings.settings or {}
        fixed_risk_percent = nested.get("fixed_risk_percent", 0.5)
        effective_risk = self._effective_max_risk_per_trade(
            account_id,
            settings.max_risk_per_trade,
            fixed_risk_percent,
            self._today(),
        )
        return {
            "max_trades_per_day": settings.max_trades_per_day,
            "max_daily_loss": settings.max_daily_loss,
            "max_daily_profit": nested.get("max_daily_profit", 0),
            "max_risk_per_trade": settings.max_risk_per_trade,
            "effective_max_risk_per_trade": effective_risk,
            "fixed_risk_percent": fixed_risk_percent,
            "trading_window_start": settings.trading_window_start,
            "trading_window_end": settings.trading_window_end,
        }

    def _effective_max_risk_per_trade(
        self,
        account_id: int | None,
        fallback_value: float | None,
        fixed_risk_percent: float | int | str | None,
        target_date: date,
    ) -> float | None:
        try:
            percent = float(fixed_risk_percent or 0)
        except (TypeError, ValueError):
            percent = 0
        account_value = self._daily_start_account_value(account_id, target_date)
        if percent > 0 and account_value > 0:
            return round(account_value * percent / 100, 2)
        return fallback_value

    def _daily_start_account_value(
        self,
        account_id: int | None,
        target_date: date,
    ) -> float:
        day_start_utc = datetime.combine(target_date, time.min) - timedelta(hours=7)
        day_end_utc = day_start_utc + timedelta(days=1)

        query = self._db.query(AccountSnapshot)
        if account_id is not None:
            query = query.filter(AccountSnapshot.account_id == account_id)

        snapshot = (
            query.filter(AccountSnapshot.captured_at <= day_start_utc)
            .order_by(AccountSnapshot.captured_at.desc(), AccountSnapshot.id.desc())
            .first()
        )
        if snapshot is not None:
            return snapshot.balance or snapshot.equity or 0

        query = self._db.query(AccountSnapshot)
        if account_id is not None:
            query = query.filter(AccountSnapshot.account_id == account_id)
        snapshot = (
            query.filter(
                AccountSnapshot.captured_at >= day_start_utc,
                AccountSnapshot.captured_at < day_end_utc,
            )
            .order_by(AccountSnapshot.captured_at.asc(), AccountSnapshot.id.asc())
            .first()
        )
        if snapshot is not None:
            return snapshot.balance or snapshot.equity or 0

        return self._latest_balance(account_id)

    def _month_bounds(self, month: str) -> tuple[date, date]:
        try:
            year, month_number = (int(part) for part in month.split("-", maxsplit=1))
            last_day = calendar.monthrange(year, month_number)[1]
            return date(year, month_number, 1), date(year, month_number, last_day)
        except ValueError as exc:
            raise HTTPException(
                status_code=422,
                detail="month must use YYYY-MM format",
            ) from exc

    def _percent(self, numerator: int, denominator: int) -> float:
        if denominator == 0:
            return 0.0
        return round((numerator / denominator) * 100, 2)

    def _profit_factor(self, trades: list[NormalizedTrade]) -> float | None:
        gross_profit = sum(trade.net_pnl for trade in trades if trade.net_pnl > 0)
        gross_loss = abs(sum(trade.net_pnl for trade in trades if trade.net_pnl < 0))
        if gross_loss == 0:
            return 999.0 if gross_profit > 0 else 0.0
        return round(gross_profit / gross_loss, 4)

    def _expectancy(self, trades: list[NormalizedTrade]) -> float:
        if not trades:
            return 0.0
        return round(sum(trade.net_pnl for trade in trades) / len(trades), 2)

