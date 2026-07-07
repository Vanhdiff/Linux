from datetime import date, datetime, time, timedelta
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import (
    AccountSnapshot,
    EconomicEvent,
    GuardrailSetting,
    NormalizedTrade,
    RawDeal,
    RawPosition,
    RuleBreak,
    TradingAccount,
)
from app.schemas.guardrail import GuardrailSettingsPatch
from app.services.block_state_service import BlockStateService
from app.application.discipline_score_service import DisciplineScoreService
from app.application.guardrail_data_collector import GuardrailDataCollector
from app.application.guardrail_block_pipeline import GuardrailBlockPipeline
from app.application.guardrail_response_builder import GuardrailResponseBuilder
from app.application.rule_break_sync_service import RuleBreakSyncService
from app.application.settings_lock_service import SettingsLockService
from app.domain.services.rule_engine import RuleEvaluationInput


class GuardrailService:
    def __init__(self, db: Session) -> None:
        self._db = db
        self._block_state = BlockStateService(db)
        self._data_collector = GuardrailDataCollector(
            db,
            trade_entry_signature=self._trade_entry_signature,
            deal_direction=self._deal_direction,
            is_open_deal=self._is_open_deal,
            position_opened_at=self._position_opened_at,
            position_volume=self._position_volume,
            position_profit=self._position_profit,
        )
        self._block_pipeline = GuardrailBlockPipeline(db)
        self._settings_lock = SettingsLockService(db, self._today)
        self._rule_break_sync = RuleBreakSyncService(
            db,
            open_rule_breaks=self._open_rule_breaks,
        )
        self._score_service = DisciplineScoreService(
            setting_enabled=self._setting_enabled,
            performance_score_rows=self._performance_score_rows,
            discipline_score_rows=self._discipline_score_rows,
            consistency_score_rows=self._consistency_score_rows,
        )
        self._response_builder = GuardrailResponseBuilder(
            trade_block_payload=self._trade_block_payload,
            guardrail_lock_payload=self._guardrail_lock_payload,
            settings_payload=self._settings_payload,
            scorecard_payload=self._scorecard,
        )

    def status(
        self,
        account_id: int,
        trade_date: date | None = None,
        floating_pnl: float | None = None,
        open_positions: list[dict] | None = None,
    ) -> dict:
        self._ensure_account(account_id)
        settings = self._get_or_create_settings(account_id)
        target_date = trade_date or self._today()
        trades = self._trades_for_day(account_id, target_date)
        opened_trades = self._trades_opened_for_day(account_id, target_date)
        live_positions = (
            open_positions
            if open_positions is not None
            else self._latest_open_positions(account_id)
        )
        trade_count = self._trade_entry_count(
            account_id,
            target_date,
            open_positions=live_positions,
        )
        live_floating_pnl = (
            floating_pnl
            if floating_pnl is not None
            else self._floating_pnl_from_positions(live_positions)
        )

        if not settings.enabled:
            return self._response_builder.build_disabled_status(
                account_id=account_id,
                target_date=target_date,
                settings=settings,
                trades=trades,
                opened_trades=opened_trades,
                trade_count=trade_count,
                floating_pnl=live_floating_pnl,
                open_positions=live_positions,
            )

        live_checks = self._block_pipeline.evaluate_rules(
            input_data=RuleEvaluationInput(
                account_id=account_id,
                target_date=target_date,
                trades=trades,
                opened_trades=opened_trades,
                open_positions=live_positions,
                floating_pnl=live_floating_pnl,
                settings=self._block_pipeline.settings_for_rule_engine(settings),
                account_value=self._daily_start_account_value(account_id, target_date),
            ),
            compatibility_checks=[
                self._daily_loss_check(
                    settings,
                    trades,
                    target_date,
                    floating_pnl=live_floating_pnl,
                ),
                self._daily_profit_check(settings, trades, target_date),
                self._trade_count_check(settings, trade_count, target_date),
                self._risk_check(settings, opened_trades, target_date),
                self._news_window_check(settings),
                self._revenge_pattern_check(opened_trades, target_date),
                self._consecutive_loss_pause_check(settings, trades, target_date),
                self._cooling_off_active_check(
                    settings,
                    opened_trades,
                    target_date,
                    open_positions=live_positions,
                ),
                self._live_averaging_loss_check(
                    settings,
                    target_date,
                    open_positions=live_positions,
                ),
                self._live_martingale_check(
                    settings,
                    target_date,
                    open_positions=live_positions,
                ),
            ],
        )
        self._sync_rule_breaks(account_id, live_checks)
        open_rule_breaks = self._open_rule_breaks(account_id)
        checks = live_checks + [self._rule_break_count_check(open_rule_breaks)]
        active_breaks = [check for check in checks if check["triggered"]]
        trade_blocking_enabled = self._setting_enabled(
            settings,
            "trade_blocking_enabled",
            False,
        )
        trade_block_reasons = self._trade_block_reasons(settings, checks)
        trade_blocked = trade_blocking_enabled and bool(trade_block_reasons)

        # ----- Block state persistence through target architecture -----
        block_state = self._block_pipeline.apply_block_decision(
            account_id=account_id,
            target_date=target_date,
            trade_block_reasons=trade_block_reasons,
            trade_blocking_enabled=trade_blocking_enabled,
        )
        if trade_blocking_enabled and block_state["active"]:
            trade_blocked = True

        return self._response_builder.build_status(
            account_id=account_id,
            target_date=target_date,
            settings=settings,
            trades=trades,
            opened_trades=opened_trades,
            checks=checks,
            active_breaks=active_breaks,
            trade_count=trade_count,
            floating_pnl=live_floating_pnl,
            open_positions=live_positions,
            trade_blocking_enabled=trade_blocking_enabled,
            trade_blocked=trade_blocked,
            trade_block_reasons=trade_block_reasons,
            block_state=block_state,
        )

    def trade_block_status(
        self,
        account_id: int,
        trade_date: date | None = None,
        floating_pnl: float | None = None,
        open_positions: list[dict] | None = None,
    ) -> dict:
        status = self.status(
            account_id,
            trade_date,
            floating_pnl=floating_pnl,
            open_positions=open_positions,
        )
        return self._response_builder.build_trade_block_status(
            status=status,
            floating_pnl=floating_pnl,
        )

    def patch_settings(
        self,
        account_id: int,
        payload: GuardrailSettingsPatch,
    ) -> GuardrailSetting:
        self._ensure_account(account_id)
        settings = self._get_or_create_settings(account_id)
        changes = payload.model_dump(exclude_unset=True)
        if not changes:
            return settings

        target_date = self._today()
        trade_count = self._trade_entry_count(account_id, target_date)
        if trade_count > 0:
            self._settings_lock.schedule_settings_for_next_day(
                settings,
                changes,
                target_date + timedelta(days=1),
            )
        else:
            self._settings_lock.apply_settings_changes(settings, changes)

        self._db.commit()
        self._db.refresh(settings)
        return settings

    def rule_breaks(
        self,
        account_id: int,
        include_resolved: bool = False,
    ) -> list[RuleBreak]:
        self._ensure_account(account_id)
        query = self._db.query(RuleBreak).filter(RuleBreak.account_id == account_id)
        if not include_resolved:
            query = query.filter(RuleBreak.resolved_at.is_(None))
        return query.order_by(RuleBreak.detected_at.desc(), RuleBreak.id.desc()).all()

    def resolve_block(self, account_id: int) -> dict:
        """Manually resolve the active trading block for an account."""
        self._ensure_account(account_id)
        return self._block_state.resolve_block(account_id)

    def block_state(self, account_id: int) -> dict:
        """Return lightweight block status for the frontend."""
        self._ensure_account(account_id)
        self._block_state.resolve_expired_blocks(account_id)
        return self._block_state.block_status(account_id)

    def _ensure_account(self, account_id: int) -> TradingAccount:
        account = self._db.get(TradingAccount, account_id)
        if account is None:
            raise HTTPException(status_code=404, detail="Account not found")
        return account

    def _get_or_create_settings(self, account_id: int) -> GuardrailSetting:
        settings = (
            self._db.query(GuardrailSetting)
            .filter(GuardrailSetting.account_id == account_id)
            .order_by(GuardrailSetting.id.desc())
            .first()
        )
        if settings is not None:
            self._settings_lock.rollover_pending_settings_if_due(settings)
            return settings

        settings = GuardrailSetting(
            account_id=account_id,
            max_daily_loss=3000,
            max_trades_per_day=5,
            max_risk_per_trade=300,
            block_high_impact_news=True,
            trading_window_start=None,
            trading_window_end=None,
            enabled=True,
            settings={
                "news_window_minutes_before": 30,
                "news_window_minutes_after": 30,
                "trade_blocking_enabled": False,
                "block_max_trades_per_day": True,
                "block_max_daily_loss": True,
                "block_max_daily_profit": True,
                "max_daily_profit": 5000,
                "fixed_risk_percent": 0.5,
                "revenge_loss_streak": 2,
                "revenge_trade_window_minutes": 90,
                "max_open_rule_breaks": 3,
                "loss_streak_block_count": 3,
                "loss_streak_block_minutes": 30,
                "cooling_off_after_loss_minutes": 15,
                "martingale_volume_multiplier": 1.5,
                "position_size_tolerance_percent": 0.2,
            },
        )
        self._db.add(settings)
        self._db.commit()
        self._db.refresh(settings)
        return settings

    def _trades_for_day(
        self,
        account_id: int,
        target_date: date,
    ) -> list[NormalizedTrade]:
        return self._data_collector.trades_for_day(account_id, target_date)

    def _trades_opened_for_day(
        self,
        account_id: int,
        target_date: date,
    ) -> list[NormalizedTrade]:
        return self._data_collector.trades_opened_for_day(account_id, target_date)

    def _trade_entry_count(
        self,
        account_id: int,
        target_date: date,
        open_positions: list[dict] | None = None,
    ) -> int:
        return self._data_collector.trade_entry_count(
            account_id,
            target_date,
            open_positions=open_positions,
        )

    def _trading_day_bounds(self, target_date: date) -> tuple[datetime, datetime]:
        return self._data_collector.trading_day_bounds(target_date)

    def _trade_entry_signature(
        self,
        *,
        symbol: str,
        direction: str,
        opened_at: datetime | None,
        volume: float,
    ) -> tuple[str, str, int, float]:
        timestamp = int((opened_at or datetime.min).timestamp())
        return (
            symbol.upper(),
            direction.lower(),
            timestamp,
            round(abs(volume), 4),
        )

    def _latest_open_positions(self, account_id: int) -> list[dict]:
        return self._data_collector.latest_open_positions(account_id)

    def _floating_pnl_from_positions(self, positions: list[dict]) -> float:
        return self._data_collector.floating_pnl_from_positions(positions)

    def _open_rule_breaks(self, account_id: int) -> list[RuleBreak]:
        return self._data_collector.open_rule_breaks(account_id)

    def _today(self) -> date:
        return datetime.now().date()

    def _guardrail_lock_payload(
        self,
        trade_blocked: bool,
        trade_count: int,
        settings: GuardrailSetting | None = None,
        target_date: date | None = None,
    ) -> dict:
        return self._settings_lock.guardrail_lock_payload(
            trade_blocked,
            trade_count,
            settings,
            target_date,
        )

    def _apply_settings_changes(
        self,
        settings: GuardrailSetting,
        changes: dict,
    ) -> None:
        self._settings_lock.apply_settings_changes(settings, changes)

    def _schedule_settings_for_next_day(
        self,
        settings: GuardrailSetting,
        changes: dict,
        effective_date: date,
    ) -> None:
        self._settings_lock.schedule_settings_for_next_day(
            settings,
            changes,
            effective_date,
        )

    def _rollover_pending_settings_if_due(self, settings: GuardrailSetting) -> None:
        self._settings_lock.rollover_pending_settings_if_due(settings)

    def _pending_update(self, settings: GuardrailSetting | None) -> dict | None:
        return self._settings_lock.pending_update(settings)

    def _pending_update_payload(
        self,
        settings: GuardrailSetting | None,
        target_date: date | None = None,
    ) -> dict | None:
        return self._settings_lock.pending_update_payload(settings, target_date)

    def _parse_iso_date(self, value: object) -> date | None:
        return self._settings_lock.parse_iso_date(value)

    def _daily_loss_check(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
        floating_pnl: float | None = None,
    ) -> dict:
        closed_pnl = round(sum(trade.net_pnl for trade in trades), 2)
        floating_value = round(floating_pnl or 0, 2)
        effective_pnl = round(closed_pnl + floating_value, 2)
        threshold = settings.max_daily_loss
        triggered = threshold is not None and effective_pnl <= -abs(threshold)
        message = (
            f"Closed PnL {closed_pnl} plus floating PnL {floating_value} "
            f"reached max daily loss {threshold}."
        )
        return self._check_payload(
            "max_daily_loss_reached",
            triggered,
            "critical",
            message,
            {
                "date": target_date.isoformat(),
                "closed_pnl": closed_pnl,
                "floating_pnl": floating_value,
                "effective_pnl": effective_pnl,
                "max_daily_loss": threshold,
            },
        )

    def _daily_profit_check(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        pnl = round(sum(trade.net_pnl for trade in trades), 2)
        threshold = self._nested_number(settings, "max_daily_profit")
        triggered = threshold is not None and pnl >= abs(threshold)
        return self._check_payload(
            "max_daily_profit_reached",
            triggered,
            "warning",
            f"Daily PnL {pnl} reached max daily profit {threshold}.",
            {
                "date": target_date.isoformat(),
                "net_pnl": pnl,
                "max_daily_profit": threshold,
            },
        )

    def _trade_count_check(
        self,
        settings: GuardrailSetting,
        trade_count: int,
        target_date: date,
    ) -> dict:
        threshold = settings.max_trades_per_day
        triggered = threshold is not None and trade_count >= threshold
        return self._check_payload(
            "too_many_trades_today",
            triggered,
            "warning",
            f"{trade_count} trades today; max allowed is {threshold}.",
            {
                "date": target_date.isoformat(),
                "trade_count": trade_count,
                "max_trades_per_day": threshold,
            },
        )

    def _risk_check(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        threshold = self._effective_max_risk_per_trade(settings, target_date)
        missing_sl = [
            trade for trade in trades if trade.stop_loss in (None, 0)
        ]
        risky = [
            trade
            for trade in trades
            if threshold is not None
            and trade.risk_amount is not None
            and trade.risk_amount > threshold
        ]
        missing_risk = [
            trade
            for trade in trades
            if trade.stop_loss not in (None, 0)
            and trade.risk_amount is None
        ]
        fixed_risk_percent = self._fixed_risk_percent(settings)
        threshold_label = (
            f"{threshold:.2f}"
            if threshold is not None
            else "not configured"
        )
        percent_label = (
            f" ({fixed_risk_percent:.2f}% of account)"
            if fixed_risk_percent is not None and fixed_risk_percent > 0
            else ""
        )
        return self._check_payload(
            "risk_too_high",
            bool(risky or missing_sl or missing_risk),
            "critical",
            (
                f"{len(risky)} trades exceeded risk per trade "
                f"{threshold_label}{percent_label}; "
                f"{len(missing_sl)} missing SL; {len(missing_risk)} missing risk."
            ),
            {
                "date": target_date.isoformat(),
                "max_risk_per_trade": threshold,
                "fixed_risk_percent": fixed_risk_percent,
                "trade_ids": [trade.id for trade in risky],
                "missing_stop_loss_trade_ids": [trade.id for trade in missing_sl],
                "missing_risk_trade_ids": [trade.id for trade in missing_risk],
            },
        )

    def _effective_max_risk_per_trade(
        self,
        settings: GuardrailSetting,
        target_date: date | None = None,
    ) -> float | None:
        fixed_risk_percent = self._fixed_risk_percent(settings)
        account_value = self._daily_start_account_value(
            settings.account_id,
            target_date or self._today(),
        )
        if (
            fixed_risk_percent is not None
            and fixed_risk_percent > 0
            and account_value > 0
        ):
            return round(account_value * fixed_risk_percent / 100, 2)
        return settings.max_risk_per_trade

    def _daily_start_account_value(self, account_id: int, target_date: date) -> float:
        day_start_utc = datetime.combine(target_date, time.min) - timedelta(hours=7)
        day_end_utc = day_start_utc + timedelta(days=1)

        snapshot = (
            self._db.query(AccountSnapshot)
            .filter(
                AccountSnapshot.account_id == account_id,
                AccountSnapshot.captured_at <= day_start_utc,
            )
            .order_by(AccountSnapshot.captured_at.desc(), AccountSnapshot.id.desc())
            .first()
        )
        if snapshot is not None:
            return self._snapshot_account_value(snapshot)

        snapshot = (
            self._db.query(AccountSnapshot)
            .filter(
                AccountSnapshot.account_id == account_id,
                AccountSnapshot.captured_at >= day_start_utc,
                AccountSnapshot.captured_at < day_end_utc,
            )
            .order_by(AccountSnapshot.captured_at.asc(), AccountSnapshot.id.asc())
            .first()
        )
        if snapshot is not None:
            return self._snapshot_account_value(snapshot)

        return self._latest_account_value(account_id)

    def _latest_account_value(self, account_id: int) -> float:
        snapshot = (
            self._db.query(AccountSnapshot)
            .filter(AccountSnapshot.account_id == account_id)
            .order_by(AccountSnapshot.captured_at.desc(), AccountSnapshot.id.desc())
            .first()
        )
        if snapshot is None:
            snapshot = (
                self._db.query(AccountSnapshot)
                .join(TradingAccount, TradingAccount.id == AccountSnapshot.account_id)
                .filter(TradingAccount.is_active.is_(True))
                .order_by(
                    AccountSnapshot.captured_at.desc(),
                    AccountSnapshot.id.desc(),
                )
                .first()
            )
        if snapshot is None:
            snapshot = (
                self._db.query(AccountSnapshot)
                .order_by(
                    AccountSnapshot.captured_at.desc(),
                    AccountSnapshot.id.desc(),
                )
                .first()
            )
        if snapshot is None:
            return 0
        return self._snapshot_account_value(snapshot)

    def _snapshot_account_value(self, snapshot: AccountSnapshot) -> float:
        return snapshot.balance or snapshot.equity or 0

    def _news_window_check(self, settings: GuardrailSetting) -> dict:
        config = settings.settings or {}
        mode = str(config.get("news_block_mode") or "Before and After").lower()
        before = int(config.get("news_window_minutes_before", 30))
        after = int(config.get("news_window_minutes_after", 30))
        now = datetime.utcnow()
        start = now if mode == "before only" else now - timedelta(minutes=after)
        end = now if mode == "after only" else now + timedelta(minutes=before)
        events = []
        if settings.block_high_impact_news:
            events = (
                self._db.query(EconomicEvent)
                .filter(
                    EconomicEvent.impact.in_(["high"]),
                    EconomicEvent.event_time >= start,
                    EconomicEvent.event_time <= end,
                )
                .order_by(EconomicEvent.event_time.asc())
                .all()
            )
        return self._check_payload(
            "high_impact_news_window",
            bool(events),
            "critical",
            f"{len(events)} red high-impact events are inside the news window.",
            {
                "window_start": start.isoformat(),
                "window_end": end.isoformat(),
                "news_block_mode": config.get("news_block_mode") or "Before and After",
                "blocking_impacts": ["high"],
                "ignored_impacts": ["medium", "low", "holiday", "unknown"],
                "event_ids": [event.id for event in events],
            },
        )

    def _revenge_pattern_check(
        self,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        cooldown_minutes = 15
        if len(trades) < 2:
            return self._check_payload(
                "revenge_trading_pattern",
                False,
                "warning",
                "No revenge trading pattern detected.",
                {"date": target_date.isoformat()},
            )

        violations = []
        ordered = sorted(
            [trade for trade in trades if trade.opened_at is not None],
            key=lambda trade: (trade.opened_at, trade.id),
        )
        for previous in ordered:
            if previous.net_pnl >= 0 or previous.closed_at is None:
                continue
            for current in ordered:
                if current.id == previous.id or current.opened_at is None:
                    continue
                if current.opened_at <= previous.closed_at:
                    continue
                if current.opened_at <= previous.closed_at + timedelta(minutes=cooldown_minutes):
                    violations.append(
                        {
                            "loss_trade_id": previous.id,
                            "trade_id": current.id,
                            "minutes_after_loss": round(
                                (current.opened_at - previous.closed_at).total_seconds() / 60,
                                2,
                            ),
                        }
                    )
                break

        return self._check_payload(
            "revenge_trading_pattern",
            bool(violations),
            "warning",
            f"{len(violations)} revenge-trade pattern(s) detected within {cooldown_minutes} minutes.",
            {
                "date": target_date.isoformat(),
                "cooldown_minutes": cooldown_minutes,
                "violations": violations,
            },
        )

    def _consecutive_loss_pause_check(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        threshold = int(self._nested_number(settings, "loss_streak_block_count") or 3)
        pause_minutes = int(
            self._nested_number(settings, "loss_streak_block_minutes") or 30
        )
        state = self._consecutive_loss_state(trades, threshold, pause_minutes)
        lock_expires_at = state["lock_expires_at"]
        return self._check_payload(
            "consecutive_losses_pause_active",
            state["active"],
            "critical",
            (
                f"{state['current_streak']} consecutive losses active. "
                f"Trading is paused until {lock_expires_at.isoformat()}."
            )
            if state["active"] and lock_expires_at is not None
            else "No active consecutive-loss pause.",
            {
                "date": target_date.isoformat(),
                "streak_threshold": threshold,
                "pause_minutes": pause_minutes,
                "max_streak": state["max_streak"],
                "current_streak": state["current_streak"],
                "violated_today": state["violated_today"],
                "lock_expires_at": (
                    lock_expires_at.isoformat() if lock_expires_at is not None else None
                ),
            },
        )

    def _cooling_off_active_check(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
        open_positions: list[dict] | None = None,
    ) -> dict:
        cooldown_minutes = int(
            self._nested_number(settings, "cooling_off_after_loss_minutes") or 15
        )
        state = self._cooling_off_state(
            trades,
            cooldown_minutes,
            open_positions=open_positions,
        )
        return self._check_payload(
            "cooling_off_active",
            state["active"],
            "critical",
            (
                f"Stop-loss cooling off is active until {state['cooldown_until']}."
                if state["active"]
                else "No active stop-loss cooling off."
            ),
            {
                "date": target_date.isoformat(),
                "cooldown_minutes": cooldown_minutes,
                **state,
            },
        )

    def _live_averaging_loss_check(
        self,
        settings: GuardrailSetting,
        target_date: date,
        open_positions: list[dict] | None = None,
    ) -> dict:
        state = self._live_averaging_loss_state(open_positions or [])
        return self._check_payload(
            "live_averaging_loss",
            state["violation_count"] > 0,
            "critical",
            (
                f"{state['violation_count']} live averaging-loss pattern(s) detected."
                if state["violation_count"] > 0
                else "No live averaging-loss pattern detected."
            ),
            {"date": target_date.isoformat(), **state},
        )

    def _live_martingale_check(
        self,
        settings: GuardrailSetting,
        target_date: date,
        open_positions: list[dict] | None = None,
    ) -> dict:
        multiplier = float(
            self._nested_number(settings, "martingale_volume_multiplier") or 1.5
        )
        state = self._live_martingale_state(open_positions or [], multiplier)
        return self._check_payload(
            "live_martingale",
            state["violation_count"] > 0,
            "critical",
            (
                f"{state['violation_count']} live martingale pattern(s) detected."
                if state["violation_count"] > 0
                else "No live martingale pattern detected."
            ),
            {"date": target_date.isoformat(), **state},
        )

    def _rule_break_count_check(self, open_rule_breaks: list[RuleBreak]) -> dict:
        count = len(open_rule_breaks)
        return self._check_payload(
            "rule_break_count",
            count >= 3,
            "warning",
            f"{count} unresolved rule breaks.",
            {"open_rule_break_count": count},
        )

    def _sync_rule_breaks(self, account_id: int, checks: list[dict]) -> None:
        self._rule_break_sync.sync_rule_breaks(account_id, checks)

    def _check_payload(
        self,
        rule_code: str,
        triggered: bool,
        severity: str,
        message: str,
        payload: dict,
    ) -> dict:
        return {
            "rule_code": rule_code,
            "triggered": triggered,
            "severity": severity if triggered else "info",
            "message": message,
            "payload": payload,
        }

    def _trade_block_reasons(
        self,
        settings: GuardrailSetting,
        checks: list[dict],
    ) -> list[dict]:
        config = settings.settings or {}
        blockable_codes = {
            "too_many_trades_today": bool(
                config.get("block_max_trades_per_day", True)
            ),
            "max_daily_loss_reached": bool(config.get("block_max_daily_loss", True)),
            "max_daily_profit_reached": bool(
                config.get("block_max_daily_profit", True)
            ),
            "risk_too_high": True,
            "high_impact_news_window": settings.block_high_impact_news,
            "consecutive_losses_pause_active": True,
            "cooling_off_active": True,
            "live_averaging_loss": True,
            "live_martingale": True,
        }
        return [
            {
                "rule_code": check["rule_code"],
                "severity": check["severity"],
                "message": check["message"],
                "payload": check["payload"],
            }
            for check in checks
            if check["triggered"] and blockable_codes.get(check["rule_code"], False)
        ]

    def _trade_block_payload(self, enabled: bool, reasons: list[dict]) -> dict:
        return {
            "enabled": enabled,
            "blocked": enabled and bool(reasons),
            "reasons": reasons,
            "reason_count": len(reasons),
        }

    def _setting_enabled(
        self,
        settings: GuardrailSetting,
        key: str,
        default: bool = True,
    ) -> bool:
        config = settings.settings or {}
        return bool(config.get(key, default))

    def _nested_number(self, settings: GuardrailSetting, key: str) -> float | None:
        config = settings.settings or {}
        value = config.get(key)
        if value is None:
            return None
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    def _fixed_risk_percent(self, settings: GuardrailSetting) -> float:
        value = self._nested_number(settings, "fixed_risk_percent")
        return value if value is not None and value > 0 else 0.5

    def _scorecard(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        opened_trades: list[NormalizedTrade],
        target_date: date,
        checks: list[dict],
        *,
        trade_count: int,
        floating_pnl: float | None = None,
        open_positions: list[dict] | None = None,
    ) -> dict:
        return self._score_service.build_scorecard(
            settings,
            trades,
            opened_trades,
            target_date,
            checks,
            trade_count=trade_count,
            floating_pnl=floating_pnl,
            open_positions=open_positions,
        )

    def _performance_score_rows(self, trades: list[NormalizedTrade]) -> dict:
        summary = self._trade_metric_summary(trades)
        rows = [
            self._score_row(
                "profit_factor",
                "Profit factor",
                7.5,
                summary["profit_factor"] >= 1.8,
                round(summary["profit_factor"], 4),
                1.8,
            ),
            self._score_row(
                "win_rate",
                "Win rate",
                7.5,
                summary["win_rate"] >= 45,
                round(summary["win_rate"], 2),
                45,
                unit="%",
            ),
            self._score_row(
                "average_rr",
                "Average RR",
                7.5,
                summary["average_rr"] >= 2,
                round(summary["average_rr"], 4),
                2,
                unit="R",
            ),
            self._score_row(
                "expectancy_r",
                "Expectancy",
                7.5,
                summary["expectancy_r"] >= 0.4,
                round(summary["expectancy_r"], 4),
                0.4,
                unit="R",
            ),
        ]
        return self._score_category("performance", "Performance", rows)

    def _discipline_score_rows(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        opened_trades: list[NormalizedTrade],
        target_date: date,
        check_map: dict[str, dict],
        *,
        trade_count: int,
        trade_blocking_enabled: bool,
        open_positions: list[dict] | None = None,
    ) -> dict:
        consecutive = self._consecutive_loss_state(
            trades,
            int(self._nested_number(settings, "loss_streak_block_count") or 3),
            int(self._nested_number(settings, "loss_streak_block_minutes") or 30),
        )
        cooling = self._cooling_off_state(
            trades,
            int(self._nested_number(settings, "cooling_off_after_loss_minutes") or 15),
            open_positions=open_positions,
        )
        averaging = self._averaging_loss_state(trades)
        live_averaging = self._live_averaging_loss_state(open_positions or [])
        martingale = self._martingale_state(
            opened_trades,
            float(self._nested_number(settings, "martingale_volume_multiplier") or 1.5),
        )
        live_martingale = self._live_martingale_state(
            open_positions or [],
            float(self._nested_number(settings, "martingale_volume_multiplier") or 1.5),
        )
        rows = [
            self._score_row(
                "daily_loss",
                "Daily loss",
                5,
                not check_map.get("max_daily_loss_reached", {}).get("triggered", False),
                round(sum(trade.net_pnl for trade in trades), 2),
                -abs(settings.max_daily_loss or 0),
                unit="$",
            ),
            self._score_row(
                "max_trades",
                "Max trades",
                5,
                not check_map.get("too_many_trades_today", {}).get("triggered", False),
                trade_count,
                settings.max_trades_per_day or 0,
                unit="trades",
            ),
            self._score_row(
                "revenge_trade",
                "Revenge trade",
                5,
                not check_map.get("revenge_trading_pattern", {}).get("triggered", False),
                1 if check_map.get("revenge_trading_pattern", {}).get("triggered", False) else 0,
                0,
            ),
            self._score_row(
                "risk_per_trade",
                "Risk per trade",
                5,
                not check_map.get("risk_too_high", {}).get("triggered", False),
                round(self._highest_risk_amount(trades), 2),
                round(self._effective_max_risk_per_trade(settings, target_date) or 0, 2),
                unit="$",
            ),
            self._score_row(
                "consecutive_loss_pause",
                "Consecutive loss pause",
                5,
                not consecutive["violated_today"],
                consecutive["max_streak"],
                consecutive["threshold"],
                unit="losses",
            ),
            self._score_row(
                "cooling_off",
                "Cooling off",
                5,
                cooling["violation_count"] == 0 and not cooling["active"],
                cooling["violation_count"],
                0,
            ),
            self._score_row(
                "no_averaging_loss",
                "No averaging loss",
                5,
                averaging["violation_count"] == 0
                and live_averaging["violation_count"] == 0,
                averaging["violation_count"] + live_averaging["violation_count"],
                0,
            ),
            self._score_row(
                "no_martingale",
                "No martingale",
                5,
                martingale["violation_count"] == 0
                and live_martingale["violation_count"] == 0,
                martingale["violation_count"] + live_martingale["violation_count"],
                0,
            ),
        ]
        category = self._score_category("discipline", "Discipline", rows)
        if not trade_blocking_enabled:
            category["earned_points"] = 0
            category["forced_zero"] = True
            category["reason"] = "Trade blocking was disabled for this day."
            for row in category["rows"]:
                row["earned_points"] = 0
        return category

    def _consistency_score_rows(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        outside = self._outside_session_state(settings, trades)
        drawdown = self._drawdown_state(settings.account_id, trades, target_date)
        position_size = self._position_size_consistency_state(
            settings,
            trades,
            target_date,
        )
        rows = [
            self._score_row(
                "max_drawdown",
                "Max Drawdown",
                10,
                drawdown["max_drawdown_percent"] < 8,
                round(drawdown["max_drawdown_percent"], 4),
                8,
                unit="%",
            ),
            self._score_row(
                "trading_time_consistency",
                "Trading Time Consistency",
                10,
                outside["configured"] and outside["violation_count"] == 0,
                (
                    outside["window_label"]
                    if outside["configured"] and outside["violation_count"] == 0
                    else (
                        "Window not set"
                        if not outside["configured"]
                        else f"{outside['violation_count']} outside"
                    )
                ),
                outside["window_label"] if outside["configured"] else "Window required",
            ),
            self._score_row(
                "position_size_consistency",
                "Position Size Consistency",
                10,
                position_size["violation_count"] == 0,
                (
                    f"{position_size['highest_trade_risk_percent']:.2f}%"
                    if position_size["trade_count"] > 0
                    else "No trades"
                ),
                position_size["range_label"],
            ),
        ]
        return self._score_category("consistency", "Consistency", rows)

    def _score_category(self, code: str, label: str, rows: list[dict]) -> dict:
        earned = round(sum(float(row["earned_points"]) for row in rows), 2)
        max_points = round(sum(float(row["max_points"]) for row in rows), 2)
        return {
            "code": code,
            "label": label,
            "earned_points": earned,
            "max_points": max_points,
            "rows": rows,
        }

    def _score_row(
        self,
        code: str,
        label: str,
        max_points: float,
        passed: bool,
        value,
        target,
        *,
        unit: str | None = None,
    ) -> dict:
        return {
            "code": code,
            "label": label,
            "passed": bool(passed),
            "earned_points": max_points if passed else 0,
            "max_points": max_points,
            "value": value,
            "target": target,
            "unit": unit,
        }

    def _trade_metric_summary(self, trades: list[NormalizedTrade]) -> dict:
        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]
        r_values = [
            float(trade.r_multiple or 0)
            for trade in trades
            if trade.r_multiple is not None
        ]
        win_r_values = [value for value in r_values if value > 0]
        loss_r_values = [abs(value) for value in r_values if value < 0]
        gross_win = sum(trade.net_pnl for trade in wins)
        gross_loss = abs(sum(trade.net_pnl for trade in losses))
        win_rate = len(wins) / len(trades) * 100 if trades else 0
        average_win_r = sum(win_r_values) / len(win_r_values) if win_r_values else 0
        average_loss_r = sum(loss_r_values) / len(loss_r_values) if loss_r_values else 0
        average_rr = average_win_r / average_loss_r if average_loss_r else 0
        win_ratio = len(wins) / len(trades) if trades else 0
        loss_ratio = len(losses) / len(trades) if trades else 0
        expectancy_r = (win_ratio * average_win_r) - (loss_ratio * average_loss_r)
        profit_factor = gross_win / gross_loss if gross_loss > 0 else 0
        return {
            "profit_factor": profit_factor,
            "win_rate": win_rate,
            "average_rr": average_rr,
            "expectancy_r": expectancy_r,
        }

    def _highest_risk_amount(self, trades: list[NormalizedTrade]) -> float:
        values = [
            float(trade.risk_amount or 0)
            for trade in trades
            if trade.risk_amount is not None
        ]
        return max(values, default=0)

    def _consecutive_loss_state(
        self,
        trades: list[NormalizedTrade],
        threshold: int,
        pause_minutes: int,
    ) -> dict:
        max_streak = 0
        current_streak = 0
        lock_expires_at = None
        now = datetime.utcnow()
        for trade in trades:
            if trade.net_pnl < 0:
                current_streak += 1
                max_streak = max(max_streak, current_streak)
                if current_streak >= threshold and trade.closed_at is not None:
                    lock_expires_at = trade.closed_at + timedelta(minutes=pause_minutes)
            else:
                current_streak = 0
        return {
            "threshold": threshold,
            "pause_minutes": pause_minutes,
            "max_streak": max_streak,
            "current_streak": current_streak,
            "violated_today": max_streak >= threshold,
            "lock_expires_at": lock_expires_at,
            "active": lock_expires_at is not None and now <= lock_expires_at,
        }

    def _cooling_off_state(
        self,
        trades: list[NormalizedTrade],
        cooldown_minutes: int,
        open_positions: list[dict] | None = None,
    ) -> dict:
        violations = []
        stop_loss_trades = [trade for trade in trades if self._is_stop_loss_trade(trade)]
        for previous, current in zip(trades, trades[1:]):
            if (
                self._is_stop_loss_trade(previous)
                and previous.closed_at is not None
                and current.opened_at is not None
                and current.opened_at < previous.closed_at + timedelta(minutes=cooldown_minutes)
            ):
                violations.append(
                    {
                        "after_trade_id": previous.id,
                        "trade_id": current.id,
                    }
                )

        now = datetime.utcnow()
        last_sl = stop_loss_trades[-1] if stop_loss_trades else None
        cooldown_until = (
            last_sl.closed_at + timedelta(minutes=cooldown_minutes)
            if last_sl is not None and last_sl.closed_at is not None
            else None
        )
        active = cooldown_until is not None and now < cooldown_until
        live_violations = []
        if active and last_sl is not None:
            for position in open_positions or []:
                opened_at = self._position_opened_at(position)
                if opened_at is not None and opened_at >= last_sl.closed_at:
                    live_violations.append(
                        {
                            "after_trade_id": last_sl.id,
                            "position": self._position_id(position),
                            "opened_at": opened_at.isoformat(),
                        }
                    )
        return {
            "cooldown_minutes": cooldown_minutes,
            "violation_count": len(violations),
            "violations": violations,
            "active": active,
            "last_stop_loss_trade_id": last_sl.id if last_sl is not None else None,
            "cooldown_until": cooldown_until.isoformat() if cooldown_until else None,
            "live_violation_count": len(live_violations),
            "live_violations": live_violations,
        }

    def _is_stop_loss_trade(self, trade: NormalizedTrade) -> bool:
        for deal in self._raw_deals_for_trade(trade):
            reason = str(
                deal.raw_payload.get("reason")
                or deal.raw_payload.get("deal_reason")
                or ""
            ).lower()
            comment = str(deal.comment or "").lower()
            if any(token in reason for token in ["sl", "stoploss", "stop_loss", "deal_reason_sl"]):
                return trade.net_pnl < 0
            if any(token in comment for token in ["sl", "stop loss", "stopped"]):
                return trade.net_pnl < 0
        text = f"{trade.exit_reason or ''} {trade.setup_tag or ''}".lower()
        if any(token in text for token in ["sl", "stop loss", "stopped"]):
            return trade.net_pnl < 0
        return trade.net_pnl < 0 and trade.r_multiple is not None and trade.r_multiple <= -0.8

    def _averaging_loss_state(self, trades: list[NormalizedTrade]) -> dict:
        violations = []
        for index, anchor in enumerate(trades):
            if anchor.net_pnl >= 0 or anchor.opened_at is None or anchor.closed_at is None:
                continue
            for current in trades[index + 1 :]:
                if current.opened_at is None:
                    continue
                if current.opened_at >= anchor.closed_at:
                    break
                if (
                    current.symbol == anchor.symbol
                    and current.direction == anchor.direction
                ):
                    violations.append(
                        {
                            "anchor_trade_id": anchor.id,
                            "trade_id": current.id,
                        }
                    )
        return {"violation_count": len(violations), "violations": violations}

    def _live_averaging_loss_state(self, positions: list[dict]) -> dict:
        grouped: dict[tuple[str, str], list[dict]] = {}
        for position in positions:
            key = (
                str(position.get("symbol") or "").upper(),
                str(position.get("direction") or "").lower(),
            )
            if not key[0] or not key[1]:
                continue
            grouped.setdefault(key, []).append(position)

        violations = []
        for (symbol, direction), items in grouped.items():
            ordered = sorted(items, key=self._position_sort_key)
            if len(ordered) < 2:
                continue
            losing = [
                item for item in ordered if self._position_profit(item) < 0
            ]
            if not losing:
                continue
            first_loser = losing[0]
            for item in ordered:
                if item is first_loser:
                    continue
                if self._position_sort_key(item) >= self._position_sort_key(first_loser):
                    violations.append(
                        {
                            "symbol": symbol,
                            "direction": direction,
                            "losing_position": self._position_id(first_loser),
                            "added_position": self._position_id(item),
                            "losing_profit": self._position_profit(first_loser),
                            "added_volume": self._position_volume(item),
                        }
                    )
        return {"violation_count": len(violations), "violations": violations}

    def _martingale_state(
        self,
        trades: list[NormalizedTrade],
        multiplier: float,
    ) -> dict:
        violations = []
        for previous, current in zip(trades, trades[1:]):
            if (
                previous.net_pnl < 0
                and previous.opened_at is not None
                and current.opened_at is not None
                and previous.symbol == current.symbol
                and previous.direction == current.direction
                and previous.volume > 0
                and current.volume >= previous.volume * multiplier
            ):
                violations.append(
                    {
                        "previous_trade_id": previous.id,
                        "trade_id": current.id,
                        "previous_volume": previous.volume,
                        "volume": current.volume,
                    }
                )
        return {
            "multiplier": multiplier,
            "violation_count": len(violations),
            "violations": violations,
        }

    def _raw_deals_for_trade(self, trade: NormalizedTrade) -> list[RawDeal]:
        source_ids = [
            str(value)
            for value in (trade.source_deal_ids or [])
            if str(value).strip()
        ]
        if not source_ids:
            return []
        return (
            self._db.query(RawDeal)
            .filter(
                RawDeal.account_id == trade.account_id,
                RawDeal.external_deal_id.in_(source_ids),
            )
            .order_by(RawDeal.deal_time.asc(), RawDeal.id.asc())
            .all()
        )

    def _is_open_deal(self, deal: RawDeal) -> bool:
        value = str(deal.entry_type or "").lower()
        return value in {"in", "entry_in", "open", "0"}

    def _deal_direction(self, deal: RawDeal) -> str:
        value = str(deal.direction or "").lower()
        return "sell" if "sell" in value or value == "1" else "buy"

    def _live_martingale_state(
        self,
        positions: list[dict],
        multiplier: float,
    ) -> dict:
        grouped: dict[tuple[str, str], list[dict]] = {}
        for position in positions:
            key = (
                str(position.get("symbol") or "").upper(),
                str(position.get("direction") or "").lower(),
            )
            if not key[0] or not key[1]:
                continue
            grouped.setdefault(key, []).append(position)

        violations = []
        for (symbol, direction), items in grouped.items():
            ordered = sorted(items, key=self._position_sort_key)
            for previous, current in zip(ordered, ordered[1:]):
                previous_volume = self._position_volume(previous)
                current_volume = self._position_volume(current)
                if (
                    previous_volume > 0
                    and self._position_profit(previous) < 0
                    and current_volume > previous_volume * multiplier
                ):
                    violations.append(
                        {
                            "symbol": symbol,
                            "direction": direction,
                            "previous_position": self._position_id(previous),
                            "position": self._position_id(current),
                            "previous_volume": previous_volume,
                            "volume": current_volume,
                            "multiplier": multiplier,
                        }
                    )
        return {
            "multiplier": multiplier,
            "violation_count": len(violations),
            "violations": violations,
        }

    def _position_sort_key(self, position: dict) -> tuple[datetime, str]:
        opened_at = self._position_opened_at(position) or datetime.min
        return opened_at, self._position_id(position)

    def _position_opened_at(self, position: dict) -> datetime | None:
        value = (
            position.get("opened_at")
            or position.get("time")
            or position.get("time_msc")
            or position.get("time_update")
        )
        if value is None:
            return None
        if isinstance(value, datetime):
            return value
        if isinstance(value, (int, float)):
            seconds = float(value)
            if seconds > 10_000_000_000:
                seconds = seconds / 1000
            return datetime.utcfromtimestamp(seconds)
        text = str(value)
        try:
            return datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            return None

    def _position_profit(self, position: dict) -> float:
        try:
            return float(position.get("profit") or 0)
        except (TypeError, ValueError):
            return 0

    def _position_volume(self, position: dict) -> float:
        try:
            return abs(float(position.get("volume") or 0))
        except (TypeError, ValueError):
            return 0

    def _position_id(self, position: dict) -> str:
        return str(
            position.get("external_position_id")
            or position.get("ticket")
            or position.get("identifier")
            or position.get("position")
            or ""
        )

    def _outside_session_state(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
    ) -> dict:
        start_minutes = self._session_minutes(settings.trading_window_start)
        end_minutes = self._session_minutes(settings.trading_window_end)
        if start_minutes is None or end_minutes is None:
            return {
                "configured": False,
                "violation_count": 0,
                "violations": [],
                "window_label": "Window required",
            }
        violations = []
        for trade in trades:
            if trade.opened_at is None:
                continue
            local_minutes = self._local_minutes(trade.opened_at)
            if not self._minutes_within_window(local_minutes, start_minutes, end_minutes):
                violations.append(
                    {
                        "trade_id": trade.id,
                        "opened_at": trade.opened_at.isoformat(),
                    }
                )
        return {
            "configured": True,
            "violation_count": len(violations),
            "violations": violations,
            "window_label": self._trading_window_label(settings),
        }

    def _drawdown_state(
        self,
        account_id: int,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        equity = 0.0
        peak = 0.0
        max_drawdown = 0.0
        for trade in trades:
            equity = round(equity + trade.net_pnl, 2)
            peak = max(peak, equity)
            max_drawdown = min(max_drawdown, round(equity - peak, 2))
        balance_base = self._daily_start_account_value(account_id, target_date)
        max_drawdown_abs = round(abs(max_drawdown), 2)
        max_drawdown_percent = (
            round(max_drawdown_abs / balance_base * 100, 4)
            if balance_base > 0
            else 0
        )
        return {
            "max_drawdown": max_drawdown_abs,
            "max_drawdown_percent": max_drawdown_percent,
            "balance_base": balance_base,
        }

    def _position_size_consistency_state(
        self,
        settings: GuardrailSetting,
        trades: list[NormalizedTrade],
        target_date: date,
    ) -> dict:
        target_risk_percent = self._fixed_risk_percent(settings)
        tolerance = self._position_size_tolerance_percent(settings)
        min_risk = max(0.0, target_risk_percent - tolerance)
        max_risk = target_risk_percent + tolerance
        account_value = self._daily_start_account_value(settings.account_id, target_date)
        risk_percents = []
        violations = []
        for trade in trades:
            if trade.risk_amount is None or account_value <= 0:
                continue
            risk_percent = round(float(trade.risk_amount) / account_value * 100, 4)
            risk_percents.append({"trade_id": trade.id, "risk_percent": risk_percent})
            if risk_percent < min_risk or risk_percent > max_risk:
                violations.append({"trade_id": trade.id, "risk_percent": risk_percent})
        return {
            "trade_count": len(risk_percents),
            "target_risk_percent": target_risk_percent,
            "tolerance_percent": tolerance,
            "min_risk_percent": min_risk,
            "max_risk_percent": max_risk,
            "range_label": f"{min_risk:.2f}%-{max_risk:.2f}%",
            "violations": violations,
            "violation_count": len(violations),
            "highest_trade_risk_percent": max(
                (entry["risk_percent"] for entry in risk_percents),
                default=0,
            ),
        }

    def _position_size_tolerance_percent(self, settings: GuardrailSetting) -> float:
        value = self._nested_number(settings, "position_size_tolerance_percent")
        return value if value is not None and value >= 0 else 0.2

    def _trading_window_label(self, settings: GuardrailSetting) -> str:
        start = settings.trading_window_start or ""
        end = settings.trading_window_end or ""
        if not start or not end:
            return "Window required"
        start_text = start.strip().split(" ")[-1]
        end_text = end.strip().split(" ")[-1]
        return f"{start_text}-{end_text}"

    def _session_minutes(self, value: str | None) -> int | None:
        if not value:
            return None
        text = value.strip().split(" ")[-1]
        try:
            hour_text, minute_text = text.split(":", 1)
            return int(hour_text) * 60 + int(minute_text)
        except (ValueError, AttributeError):
            return None

    def _local_minutes(self, value: datetime) -> int:
        return value.hour * 60 + value.minute

    def _minutes_within_window(
        self,
        value: int,
        start_minutes: int,
        end_minutes: int,
    ) -> bool:
        if start_minutes <= end_minutes:
            return start_minutes <= value <= end_minutes
        return value >= start_minutes or value <= end_minutes

    def _settings_payload(
        self,
        settings: GuardrailSetting,
        target_date: date | None = None,
    ) -> dict:
        nested = dict(settings.settings or {})
        nested.setdefault("fixed_risk_percent", 0.5)
        nested.setdefault("loss_streak_block_count", 3)
        nested.setdefault("loss_streak_block_minutes", 30)
        nested.setdefault("cooling_off_after_loss_minutes", 15)
        nested.setdefault("martingale_volume_multiplier", 1.5)
        nested.setdefault("position_size_tolerance_percent", 0.2)
        nested["pending_update"] = self._pending_update_payload(settings, target_date)
        return {
            "id": settings.id,
            "account_id": settings.account_id,
            "max_daily_loss": settings.max_daily_loss,
            "max_trades_per_day": settings.max_trades_per_day,
            "max_risk_per_trade": settings.max_risk_per_trade,
            "effective_max_risk_per_trade": self._effective_max_risk_per_trade(
                settings,
                target_date,
            ),
            "block_high_impact_news": settings.block_high_impact_news,
            "trading_window_start": settings.trading_window_start,
            "trading_window_end": settings.trading_window_end,
            "enabled": settings.enabled,
            "settings": nested,
        }
