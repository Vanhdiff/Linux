"""
Value objects for rule violations.

These are immutable value objects that represent rule violations
detected by the rule engine.
"""
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any


class Severity(Enum):
    """Severity level of a rule violation."""
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


class RuleCode(Enum):
    """Codes for different guardrail rules."""
    MAX_DAILY_LOSS = "max_daily_loss_reached"
    MAX_TRADES_PER_DAY = "too_many_trades_today"
    MAX_DAILY_PROFIT = "max_daily_profit_reached"
    RISK_TOO_HIGH = "risk_too_high"
    NEWS_WINDOW = "high_impact_news_window"
    REVENGE_PATTERN = "revenge_trading_pattern"
    CONSECUTIVE_LOSSES = "consecutive_losses_pause_active"
    COOLING_OFF = "cooling_off_active"
    LIVE_AVERAGING = "live_averaging_loss"
    LIVE_MARTINGALE = "live_martingale"

    @classmethod
    def from_string(cls, value: str) -> "RuleCode":
        """Create RuleCode from string value."""
        try:
            return cls(value)
        except ValueError:
            # Return a generic code for unknown values
            return value  # type: ignore

    def is_full_day_blocking(self) -> bool:
        """Rules that trigger full-day block."""
        return self in {
            RuleCode.MAX_DAILY_LOSS,
            RuleCode.MAX_TRADES_PER_DAY,
            RuleCode.MAX_DAILY_PROFIT,
        }

    def is_temporary_blocking(self) -> bool:
        """Rules that trigger temporary block."""
        return self in {
            RuleCode.NEWS_WINDOW,
            RuleCode.REVENGE_PATTERN,
            RuleCode.CONSECUTIVE_LOSSES,
            RuleCode.COOLING_OFF,
            RuleCode.LIVE_AVERAGING,
            RuleCode.LIVE_MARTINGALE,
            RuleCode.RISK_TOO_HIGH,
        }


# Rules that cause full-day blocks
FULL_DAY_BLOCK_CODES = {
    "max_daily_loss_reached",
    "too_many_trades_today",
    "max_daily_profit_reached",
}

# Rules that cause temporary blocks
TEMPORARY_BLOCK_CODES = {
    "high_impact_news_window",
    "revenge_trading_pattern",
    "consecutive_losses_pause_active",
    "cooling_off_active",
    "live_averaging_loss",
    "live_martingale",
    "risk_too_high",
}


@dataclass(frozen=True)
class RuleViolation:
    """
    Immutable value object representing a rule violation.

    Contains all information about a triggered guardrail rule.
    """
    code: RuleCode
    severity: Severity
    message: str
    triggered_at: datetime = field(default_factory=datetime.now)
    payload: dict = field(default_factory=dict)

    def is_blocking(self) -> bool:
        """Returns True if this violation should block trading."""
        blocking_rules = {
            RuleCode.MAX_DAILY_LOSS,
            RuleCode.MAX_TRADES_PER_DAY,
            RuleCode.MAX_DAILY_PROFIT,
            RuleCode.NEWS_WINDOW,
            RuleCode.REVENGE_PATTERN,
            RuleCode.CONSECUTIVE_LOSSES,
            RuleCode.COOLING_OFF,
            RuleCode.LIVE_AVERAGING,
            RuleCode.LIVE_MARTINGALE,
            RuleCode.RISK_TOO_HIGH,
        }
        return self.code in blocking_rules and self.severity == Severity.CRITICAL

    def is_full_day_block(self) -> bool:
        """Check if this violation should cause a full-day block."""
        return self.code.is_full_day_blocking() and self.severity == Severity.CRITICAL

    def is_temporary_block(self) -> bool:
        """Check if this violation should cause a temporary block."""
        return self.code.is_temporary_blocking() and self.severity == Severity.CRITICAL

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "code": self.code.value,
            "severity": self.severity.value,
            "message": self.message,
            "triggered_at": self.triggered_at.isoformat(),
            "payload": self.payload,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "RuleViolation":
        """Create from dictionary."""
        return cls(
            code=RuleCode(data.get("code", "")),
            severity=Severity(data.get("severity", "warning")),
            message=data.get("message", ""),
            triggered_at=datetime.fromisoformat(data["triggered_at"]) if data.get("triggered_at") else datetime.now(),
            payload=data.get("payload", {}),
        )
