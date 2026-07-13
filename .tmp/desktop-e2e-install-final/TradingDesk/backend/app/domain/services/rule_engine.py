"""
Rule Engine - Pure domain service for evaluating guardrail rules.

This engine only evaluates rules and returns results.
It NEVER creates blocks, never accesses database, never calls UI.
"""
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from typing import Any, Optional

from app.domain.entities.rule_violation import (
    RuleCode,
    RuleViolation,
    Severity,
)


@dataclass
class RuleEvaluationInput:
    """
    Input data required for rule evaluation.

    All data must be provided from external sources.
    This class is immutable.
    """
    account_id: int
    target_date: date
    trades: list[Any] = field(default_factory=list)
    opened_trades: list[Any] = field(default_factory=list)
    open_positions: list[dict] = field(default_factory=list)
    floating_pnl: float = 0.0
    settings: Optional[dict] = None
    raw_deals: list[Any] = field(default_factory=list)
    account_value: float = 0.0


@dataclass
class RuleEvaluationResult:
    """
    Result of rule evaluation.

    Contains all triggered checks without side effects.
    """
    account_id: int
    target_date: date
    checks: list[dict] = field(default_factory=list)
    triggered_count: int = 0
    critical_count: int = 0
    warning_count: int = 0

    @property
    def has_blocking_violations(self) -> bool:
        """Check if any critical violations that should block trading exist."""
        return any(
            check.get("triggered") and check.get("severity") == "critical"
            for check in self.checks
        )

    @property
    def triggered_rule_codes(self) -> list[str]:
        """Get list of triggered rule codes."""
        return [
            check["rule_code"]
            for check in self.checks
            if check.get("triggered")
        ]


class RuleEngine:
    """
    Pure rule evaluation engine.

    Responsibilities:
    - Evaluate all guardrail rules against input data
    - Return evaluation results (checks, violations)
    - NEVER: create blocks, access database, call UI

    This is a stateless service - all data comes in via evaluate().
    """

    def __init__(self):
        """Initialize the rule engine."""
        pass

    def evaluate(self, input_data: RuleEvaluationInput) -> RuleEvaluationResult:
        """
        Evaluate all rules against the input data.

        Args:
            input_data: All data needed for rule evaluation

        Returns:
            RuleEvaluationResult with all check results
        """
        checks = []

        # Run all rule checks
        checks.append(self._daily_loss_check(input_data))
        checks.append(self._daily_profit_check(input_data))
        checks.append(self._trade_count_check(input_data))
        checks.append(self._risk_check(input_data))
        checks.append(self._news_window_check(input_data))
        checks.append(self._revenge_pattern_check(input_data))
        checks.append(self._consecutive_loss_pause_check(input_data))
        checks.append(self._cooling_off_active_check(input_data))
        checks.append(self._live_averaging_loss_check(input_data))
        checks.append(self._live_martingale_check(input_data))

        # Count triggered rules
        active_breaks = [c for c in checks if c["triggered"]]
        critical_count = len([
            c for c in active_breaks
            if c.get("severity") == "critical"
        ])
        warning_count = len([
            c for c in active_breaks
            if c.get("severity") == "warning"
        ])

        return RuleEvaluationResult(
            account_id=input_data.account_id,
            target_date=input_data.target_date,
            checks=checks,
            triggered_count=len(active_breaks),
            critical_count=critical_count,
            warning_count=warning_count,
        )

    def _daily_loss_check(self, data: RuleEvaluationInput) -> dict:
        """Check if daily loss threshold is exceeded."""
        settings = data.settings or {}
        closed_pnl = round(sum(getattr(trade, "net_pnl", 0) or 0 for trade in data.trades), 2)
        floating_value = round(data.floating_pnl or 0, 2)
        effective_pnl = round(closed_pnl + floating_value, 2)

        # Get max_daily_loss from settings (default 3000)
        max_daily_loss = settings.get("max_daily_loss") or 3000
        threshold = max_daily_loss
        triggered = threshold is not None and effective_pnl <= -abs(threshold)

        return self._check_payload(
            "max_daily_loss_reached",
            triggered,
            "critical",
            (
                f"Closed PnL {closed_pnl} plus floating PnL {floating_value} "
                f"reached max daily loss {threshold}."
            ),
            {
                "date": data.target_date.isoformat(),
                "closed_pnl": closed_pnl,
                "floating_pnl": floating_value,
                "effective_pnl": effective_pnl,
                "max_daily_loss": threshold,
            },
        )

    def _daily_profit_check(self, data: RuleEvaluationInput) -> dict:
        """Check if daily profit threshold is exceeded."""
        settings = data.settings or {}
        pnl = round(sum(getattr(trade, "net_pnl", 0) or 0 for trade in data.trades), 2)
        threshold = settings.get("max_daily_profit")
        triggered = threshold is not None and pnl >= abs(threshold)

        return self._check_payload(
            "max_daily_profit_reached",
            triggered,
            "warning",
            f"Daily PnL {pnl} reached max daily profit {threshold}.",
            {
                "date": data.target_date.isoformat(),
                "net_pnl": pnl,
                "max_daily_profit": threshold,
            },
        )

    def _trade_count_check(self, data: RuleEvaluationInput) -> dict:
        """Check if trade count exceeds limit."""
        settings = data.settings or {}
        threshold = settings.get("max_trades_per_day") or 5

        # Calculate trade count from deals and positions
        trade_count = self._calculate_trade_count(data)

        triggered = threshold is not None and trade_count >= threshold

        return self._check_payload(
            "too_many_trades_today",
            triggered,
            "warning",
            f"{trade_count} trades today; max allowed is {threshold}.",
            {
                "date": data.target_date.isoformat(),
                "trade_count": trade_count,
                "max_trades_per_day": threshold,
            },
        )

    def _risk_check(self, data: RuleEvaluationInput) -> dict:
        """Check if any trade exceeds risk limits."""
        settings = data.settings or {}
        threshold = self._effective_max_risk_per_trade(settings, data.account_value)
        trades = data.trades

        missing_sl = [trade for trade in trades if getattr(trade, "stop_loss", None) in (None, 0)]
        risky = [
            trade
            for trade in trades
            if threshold is not None
            and getattr(trade, "risk_amount", None) is not None
            and trade.risk_amount > threshold
        ]
        missing_risk = [
            trade
            for trade in trades
            if getattr(trade, "stop_loss", None) not in (None, 0)
            and getattr(trade, "risk_amount", None) is None
        ]

        fixed_risk_percent = settings.get("fixed_risk_percent", 0.5) or 0.5
        threshold_label = f"{threshold:.2f}" if threshold is not None else "not configured"
        percent_label = f" ({fixed_risk_percent:.2f}% of account)" if fixed_risk_percent > 0 else ""

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
                "date": data.target_date.isoformat(),
                "max_risk_per_trade": threshold,
                "fixed_risk_percent": fixed_risk_percent,
                "trade_ids": [trade.id for trade in risky],
                "missing_stop_loss_trade_ids": [trade.id for trade in missing_sl],
                "missing_risk_trade_ids": [trade.id for trade in missing_risk],
            },
        )

    def _news_window_check(self, data: RuleEvaluationInput) -> dict:
        """Check if in high-impact news window."""
        settings = data.settings or {}
        config = settings.get("settings", {}) if isinstance(settings.get("settings"), dict) else {}
        mode = str(config.get("news_block_mode") or "Before and After").lower()
        before = int(config.get("news_window_minutes_before", 30))
        after = int(config.get("news_window_minutes_after", 30))

        # For now, return empty - requires database access for events
        # This will be enhanced later to accept external events
        events = []

        return self._check_payload(
            "high_impact_news_window",
            bool(events),
            "critical",
            f"{len(events)} red high-impact events are inside the news window.",
            {
                "window_start": None,
                "window_end": None,
                "news_block_mode": config.get("news_block_mode") or "Before and After",
                "blocking_impacts": ["high"],
                "ignored_impacts": ["medium", "low", "holiday", "unknown"],
                "event_ids": [e.get("id") for e in events] if events else [],
            },
        )

    def _revenge_pattern_check(self, data: RuleEvaluationInput) -> dict:
        """Check for revenge trading patterns."""
        cooldown_minutes = 15
        trades = [t for t in data.trades if getattr(t, "opened_at", None) is not None]

        if len(trades) < 2:
            return self._check_payload(
                "revenge_trading_pattern",
                False,
                "warning",
                "No revenge trading pattern detected.",
                {"date": data.target_date.isoformat()},
            )

        violations = []
        ordered = sorted(trades, key=lambda t: (t.opened_at, t.id))

        for previous in ordered:
            if getattr(previous, "net_pnl", 0) >= 0 or previous.closed_at is None:
                continue
            for current in ordered:
                if current.id == previous.id or current.opened_at is None:
                    continue
                if current.opened_at <= previous.closed_at:
                    continue
                if current.opened_at <= previous.closed_at + timedelta(minutes=cooldown_minutes):
                    violations.append({
                        "loss_trade_id": previous.id,
                        "trade_id": current.id,
                        "minutes_after_loss": round(
                            (current.opened_at - previous.closed_at).total_seconds() / 60, 2
                        ),
                    })
                break

        return self._check_payload(
            "revenge_trading_pattern",
            bool(violations),
            "warning",
            f"{len(violations)} revenge-trade pattern(s) detected within {cooldown_minutes} minutes.",
            {
                "date": data.target_date.isoformat(),
                "cooldown_minutes": cooldown_minutes,
                "violations": violations,
            },
        )

    def _consecutive_loss_pause_check(self, data: RuleEvaluationInput) -> dict:
        """Check if consecutive loss pause is active."""
        settings = data.settings or {}
        config = settings.get("settings", {}) if isinstance(settings.get("settings"), dict) else {}
        threshold = int(config.get("loss_streak_block_count") or 3)
        pause_minutes = int(config.get("loss_streak_block_minutes") or 30)

        trades = data.trades
        max_streak = 0
        current_streak = 0
        lock_expires_at = None
        now = datetime.utcnow()

        for trade in trades:
            if getattr(trade, "net_pnl", 0) < 0:
                current_streak += 1
                max_streak = max(max_streak, current_streak)
                if current_streak >= threshold and trade.closed_at is not None:
                    lock_expires_at = trade.closed_at + timedelta(minutes=pause_minutes)
            else:
                current_streak = 0

        active = lock_expires_at is not None and now <= lock_expires_at

        return self._check_payload(
            "consecutive_losses_pause_active",
            active,
            "critical",
            (
                f"{max_streak} consecutive losses active. "
                f"Trading is paused until {lock_expires_at.isoformat()}."
            )
            if active and lock_expires_at is not None
            else "No active consecutive-loss pause.",
            {
                "date": data.target_date.isoformat(),
                "streak_threshold": threshold,
                "pause_minutes": pause_minutes,
                "max_streak": max_streak,
                "current_streak": current_streak,
                "violated_today": max_streak >= threshold,
                "lock_expires_at": lock_expires_at.isoformat() if lock_expires_at else None,
            },
        )

    def _cooling_off_active_check(self, data: RuleEvaluationInput) -> dict:
        """Check if cooling off period is active after a loss."""
        settings = data.settings or {}
        config = settings.get("settings", {}) if isinstance(settings.get("settings"), dict) else {}
        cooldown_minutes = int(config.get("cooling_off_after_loss_minutes") or 15)

        trades = data.trades
        violations = []
        stop_loss_trades = [t for t in trades if self._is_stop_loss_trade(t)]

        for previous, current in zip(trades, trades[1:]):
            if (
                self._is_stop_loss_trade(previous)
                and previous.closed_at is not None
                and current.opened_at is not None
                and current.opened_at < previous.closed_at + timedelta(minutes=cooldown_minutes)
            ):
                violations.append({
                    "after_trade_id": previous.id,
                    "trade_id": current.id,
                })

        now = datetime.utcnow()
        last_sl = stop_loss_trades[-1] if stop_loss_trades else None
        cooldown_until = (
            last_sl.closed_at + timedelta(minutes=cooldown_minutes)
            if last_sl is not None and last_sl.closed_at is not None
            else None
        )
        active = cooldown_until is not None and now < cooldown_until

        # Check for live violations
        live_violations = []
        if active and last_sl is not None:
            for position in data.open_positions:
                opened_at = self._position_opened_at(position)
                if opened_at is not None and opened_at >= last_sl.closed_at:
                    live_violations.append({
                        "after_trade_id": last_sl.id,
                        "position": self._position_id(position),
                        "opened_at": opened_at.isoformat(),
                    })

        return self._check_payload(
            "cooling_off_active",
            active,
            "critical",
            (
                f"Stop-loss cooling off is active until {cooldown_until}."
                if active
                else "No active stop-loss cooling off."
            ),
            {
                "date": data.target_date.isoformat(),
                "cooldown_minutes": cooldown_minutes,
                "violation_count": len(violations),
                "violations": violations,
                "active": active,
                "last_stop_loss_trade_id": last_sl.id if last_sl is not None else None,
                "cooldown_until": cooldown_until.isoformat() if cooldown_until else None,
                "live_violation_count": len(live_violations),
                "live_violations": live_violations,
            },
        )

    def _live_averaging_loss_check(self, data: RuleEvaluationInput) -> dict:
        """Check for live averaging loss patterns."""
        positions = data.open_positions or []

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
            losing = [item for item in ordered if self._position_profit(item) < 0]
            if not losing:
                continue
            first_loser = losing[0]
            for item in ordered:
                if item is first_loser:
                    continue
                if self._position_sort_key(item) >= self._position_sort_key(first_loser):
                    violations.append({
                        "symbol": symbol,
                        "direction": direction,
                        "losing_position": self._position_id(first_loser),
                        "added_position": self._position_id(item),
                        "losing_profit": self._position_profit(first_loser),
                        "added_volume": self._position_volume(item),
                    })

        return self._check_payload(
            "live_averaging_loss",
            len(violations) > 0,
            "critical",
            (
                f"{len(violations)} live averaging-loss pattern(s) detected."
                if len(violations) > 0
                else "No live averaging-loss pattern detected."
            ),
            {"date": data.target_date.isoformat(), "violation_count": len(violations), "violations": violations},
        )

    def _live_martingale_check(self, data: RuleEvaluationInput) -> dict:
        """Check for live martingale patterns."""
        settings = data.settings or {}
        config = settings.get("settings", {}) if isinstance(settings.get("settings"), dict) else {}
        multiplier = float(config.get("martingale_volume_multiplier") or 1.5)

        positions = data.open_positions or []

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
                    violations.append({
                        "symbol": symbol,
                        "direction": direction,
                        "previous_position": self._position_id(previous),
                        "position": self._position_id(current),
                        "previous_volume": previous_volume,
                        "volume": current_volume,
                        "multiplier": multiplier,
                    })

        return self._check_payload(
            "live_martingale",
            len(violations) > 0,
            "critical",
            (
                f"{len(violations)} live martingale pattern(s) detected."
                if len(violations) > 0
                else "No live martingale pattern detected."
            ),
            {"date": data.target_date.isoformat(), "multiplier": multiplier, "violation_count": len(violations), "violations": violations},
        )

    def _calculate_trade_count(self, data: RuleEvaluationInput) -> int:
        """Calculate total trade count for the day."""
        trade_keys = set()

        # Add trades opened today
        for trade in data.opened_trades:
            trade_keys.add(self._trade_entry_signature(
                symbol=getattr(trade, "symbol", "") or "",
                direction=getattr(trade, "direction", "") or "",
                opened_at=getattr(trade, "opened_at", None),
                volume=getattr(trade, "volume", 0) or 0,
            ))

        # Add open positions opened today
        for position in data.open_positions:
            opened_at = self._position_opened_at(position)
            if opened_at is None:
                continue
            trade_keys.add(self._trade_entry_signature(
                symbol=str(position.get("symbol") or ""),
                direction=str(position.get("direction") or ""),
                opened_at=opened_at,
                volume=self._position_volume(position),
            ))

        return len(trade_keys)

    def _trade_entry_signature(
        self,
        symbol: str,
        direction: str,
        opened_at: datetime | None,
        volume: float,
    ) -> tuple[str, str, int, float]:
        """Create unique signature for a trade entry."""
        timestamp = int((opened_at or datetime.min).timestamp())
        return (symbol.upper(), direction.lower(), timestamp, round(abs(volume), 4))

    def _effective_max_risk_per_trade(self, settings: dict, account_value: float) -> float | None:
        """Calculate effective max risk per trade based on account value."""
        fixed_risk_percent = settings.get("fixed_risk_percent") or 0.5
        max_risk = settings.get("max_risk_per_trade") or 300

        if fixed_risk_percent and fixed_risk_percent > 0 and account_value > 0:
            return round(account_value * fixed_risk_percent / 100, 2)
        return max_risk

    def _is_stop_loss_trade(self, trade: Any) -> bool:
        """Check if trade was closed by stop loss."""
        text = f"{getattr(trade, 'exit_reason', '') or ''} {getattr(trade, 'setup_tag', '') or ''}".lower()
        if any(token in text for token in ["sl", "stop loss", "stopped"]):
            return getattr(trade, "net_pnl", 0) < 0
        return getattr(trade, "net_pnl", 0) < 0 and getattr(trade, "r_multiple", None) is not None and trade.r_multiple <= -0.8

    def _position_sort_key(self, position: dict) -> tuple[datetime, str]:
        """Get sort key for position."""
        opened_at = self._position_opened_at(position) or datetime.min
        return opened_at, self._position_id(position)

    def _position_opened_at(self, position: dict) -> datetime | None:
        """Extract opened_at from position dict."""
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
        """Extract profit from position dict."""
        try:
            return float(position.get("profit") or 0)
        except (TypeError, ValueError):
            return 0

    def _position_volume(self, position: dict) -> float:
        """Extract volume from position dict."""
        try:
            return abs(float(position.get("volume") or 0))
        except (TypeError, ValueError):
            return 0

    def _position_id(self, position: dict) -> str:
        """Extract position ID from position dict."""
        return str(
            position.get("external_position_id")
            or position.get("ticket")
            or position.get("identifier")
            or position.get("position")
            or ""
        )

    def _check_payload(
        self,
        rule_code: str,
        triggered: bool,
        severity: str,
        message: str,
        payload: dict,
    ) -> dict:
        """Create a check result payload."""
        return {
            "rule_code": rule_code,
            "triggered": triggered,
            "severity": severity if triggered else "info",
            "message": message,
            "payload": payload,
        }
