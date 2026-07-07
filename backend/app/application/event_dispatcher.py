"""
In-Process Event Dispatcher for Block Trade events.

Supports:
- BlockCreated
- BlockResolved
- BlockExpired
- RuleTriggered

Subscribers:
- Audit Logger
- Dashboard
- Journal
- MT5 Block Executor
"""
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Callable, Generic, TypeVar

logger = logging.getLogger(__name__)


class EventType(Enum):
    """Types of events emitted by the guardrail system."""
    BLOCK_CREATED = "block_created"
    BLOCK_RESOLVED = "block_resolved"
    BLOCK_EXPIRED = "block_expired"
    RULE_TRIGGERED = "rule_triggered"


T = TypeVar("T", bound="BaseEvent")


@dataclass
class BaseEvent:
    """Base class for all events."""
    event_type: EventType
    account_id: int
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict = field(default_factory=dict)


@dataclass
class BlockCreatedEvent(BaseEvent):
    """Event emitted when a block is created."""
    block_id: int = 0
    block_type: str = ""
    triggered_by: list[str] = field(default_factory=list)
    reason: str = ""

    def __post_init__(self):
        self.event_type = EventType.BLOCK_CREATED


@dataclass
class BlockResolvedEvent(BaseEvent):
    """Event emitted when a block is resolved."""
    block_id: int = 0
    resolved_by: str = ""  # "manual" or "auto"

    def __post_init__(self):
        self.event_type = EventType.BLOCK_RESOLVED


@dataclass
class BlockExpiredEvent(BaseEvent):
    """Event emitted when a block expires."""
    block_id: int = 0

    def __post_init__(self):
        self.event_type = EventType.BLOCK_EXPIRED


@dataclass
class RuleTriggeredEvent(BaseEvent):
    """Event emitted when a rule is triggered."""
    rule_code: str = ""
    severity: str = ""
    message: str = ""
    payload: dict = field(default_factory=dict)

    def __post_init__(self):
        self.event_type = EventType.RULE_TRIGGERED


EventHandler = Callable[[BaseEvent], None]


class EventDispatcher:
    """
    In-process event dispatcher.

    Supports synchronous event dispatching to registered handlers.
    No external message queues - all events are handled in-process.
    """

    def __init__(self):
        self._handlers: dict[EventType, list[EventHandler]] = {
            EventType.BLOCK_CREATED: [],
            EventType.BLOCK_RESOLVED: [],
            EventType.BLOCK_EXPIRED: [],
            EventType.RULE_TRIGGERED: [],
        }
        self._logger = logging.getLogger("block_events")

    def subscribe(
        self,
        event_type: EventType,
        handler: EventHandler,
    ) -> None:
        """Register a handler for an event type."""
        if event_type not in self._handlers:
            self._handlers[event_type] = []
        self._handlers[event_type].append(handler)
        self._logger.debug(f"Handler registered for {event_type.value}")

    def unsubscribe(
        self,
        event_type: EventType,
        handler: EventHandler,
    ) -> None:
        """Remove a handler for an event type."""
        if event_type in self._handlers:
            try:
                self._handlers[event_type].remove(handler)
                self._logger.debug(f"Handler unregistered for {event_type.value}")
            except ValueError:
                pass

    def dispatch(self, event: BaseEvent) -> None:
        """Dispatch an event to all registered handlers."""
        handlers = self._handlers.get(event.event_type, [])

        if not handlers:
            self._logger.debug(f"No handlers for {event.event_type.value}")
            return

        self._logger.info(
            f"Dispatching {event.event_type.value} to {len(handlers)} handlers"
        )

        for handler in handlers:
            try:
                handler(event)
            except Exception as e:
                self._logger.error(
                    f"Handler error for {event.event_type.value}: {e}",
                    exc_info=True,
                )

    def dispatch_block_created(
        self,
        account_id: int,
        block_id: int,
        block_type: str,
        triggered_by: list[str],
        reason: str = "",
    ) -> None:
        """Convenience method to dispatch BlockCreatedEvent."""
        event = BlockCreatedEvent(
            account_id=account_id,
            block_id=block_id,
            block_type=block_type,
            triggered_by=triggered_by,
            reason=reason,
        )
        self.dispatch(event)

    def dispatch_block_resolved(
        self,
        account_id: int,
        block_id: int,
        resolved_by: str,
    ) -> None:
        """Convenience method to dispatch BlockResolvedEvent."""
        event = BlockResolvedEvent(
            account_id=account_id,
            block_id=block_id,
            resolved_by=resolved_by,
        )
        self.dispatch(event)

    def dispatch_block_expired(
        self,
        account_id: int,
        block_id: int,
    ) -> None:
        """Convenience method to dispatch BlockExpiredEvent."""
        event = BlockExpiredEvent(
            account_id=account_id,
            block_id=block_id,
        )
        self.dispatch(event)

    def dispatch_rule_triggered(
        self,
        account_id: int,
        rule_code: str,
        severity: str,
        message: str,
        payload: dict | None = None,
    ) -> None:
        """Convenience method to dispatch RuleTriggeredEvent."""
        event = RuleTriggeredEvent(
            account_id=account_id,
            rule_code=rule_code,
            severity=severity,
            message=message,
            payload=payload or {},
        )
        self.dispatch(event)


# ------------------------------------------------------------------
# Subscriber implementations
# ------------------------------------------------------------------

class AuditLoggerSubscriber:
    """Subscriber that logs all events for audit purposes."""

    def __init__(self):
        self._logger = logging.getLogger("audit.subscriber")

    def handle_block_created(self, event: BaseEvent) -> None:
        """Handle block created event."""
        if isinstance(event, BlockCreatedEvent):
            self._logger.info(
                f"AUDIT: Block created | account={event.account_id} "
                f"block_id={event.block_id} type={event.block_type} "
                f"triggered_by={event.triggered_by}"
            )

    def handle_block_resolved(self, event: BaseEvent) -> None:
        """Handle block resolved event."""
        if isinstance(event, BlockResolvedEvent):
            self._logger.info(
                f"AUDIT: Block resolved | account={event.account_id} "
                f"block_id={event.block_id} resolved_by={event.resolved_by}"
            )

    def handle_block_expired(self, event: BaseEvent) -> None:
        """Handle block expired event."""
        if isinstance(event, BlockExpiredEvent):
            self._logger.info(
                f"AUDIT: Block expired | account={event.account_id} "
                f"block_id={event.block_id}"
            )

    def handle_rule_triggered(self, event: BaseEvent) -> None:
        """Handle rule triggered event."""
        if isinstance(event, RuleTriggeredEvent):
            self._logger.info(
                f"AUDIT: Rule triggered | account={event.account_id} "
                f"rule={event.rule_code} severity={event.severity}"
            )


class DashboardSubscriber:
    """Subscriber that notifies dashboard of block events."""

    def __init__(self):
        self._logger = logging.getLogger("dashboard.subscriber")

    def handle_block_created(self, event: BaseEvent) -> None:
        """Notify dashboard of block creation."""
        if isinstance(event, BlockCreatedEvent):
            self._logger.info(
                f"DASHBOARD: Block created for account {event.account_id} - "
                f"dashboard should refresh"
            )

    def handle_block_resolved(self, event: BaseEvent) -> None:
        """Notify dashboard of block resolution."""
        if isinstance(event, BlockResolvedEvent):
            self._logger.info(
                f"DASHBOARD: Block resolved for account {event.account_id} - "
                f"dashboard should refresh"
            )

    def handle_block_expired(self, event: BaseEvent) -> None:
        """Notify dashboard of block expiration."""
        if isinstance(event, BlockExpiredEvent):
            self._logger.info(
                f"DASHBOARD: Block expired for account {event.account_id} - "
                f"dashboard should refresh"
            )

    def handle_rule_triggered(self, event: BaseEvent) -> None:
        """Notify dashboard of rule trigger."""
        if isinstance(event, RuleTriggeredEvent):
            self._logger.debug(
                f"DASHBOARD: Rule {event.rule_code} triggered for account {event.account_id}"
            )


class JournalSubscriber:
    """Subscriber that records block events to journal."""

    def __init__(self):
        self._logger = logging.getLogger("journal.subscriber")

    def handle_block_created(self, event: BaseEvent) -> None:
        """Record block creation to journal."""
        if isinstance(event, BlockCreatedEvent):
            self._logger.info(
                f"JOURNAL: Block {event.block_id} created for account {event.account_id}"
            )

    def handle_block_resolved(self, event: BaseEvent) -> None:
        """Record block resolution to journal."""
        if isinstance(event, BlockResolvedEvent):
            self._logger.info(
                f"JOURNAL: Block {event.block_id} resolved for account {event.account_id}"
            )

    def handle_rule_triggered(self, event: BaseEvent) -> None:
        """Record rule trigger to journal."""
        if isinstance(event, RuleTriggeredEvent):
            self._logger.info(
                f"JOURNAL: Rule {event.rule_code} triggered - {event.message}"
            )


class MT5BlockExecutorSubscriber:
    """Subscriber that triggers MT5 block enforcement."""

    def __init__(self):
        self._logger = logging.getLogger("mt5_executor.subscriber")

    def handle_block_created(self, event: BaseEvent) -> None:
        """Trigger MT5 enforcement for new block."""
        if isinstance(event, BlockCreatedEvent):
            self._logger.info(
                f"MT5: Preparing block enforcement for account {event.account_id} - "
                f"type={event.block_type}"
            )

    def handle_block_resolved(self, event: BaseEvent) -> None:
        """Remove MT5 block when resolved."""
        if isinstance(event, BlockResolvedEvent):
            self._logger.info(
                f"MT5: Removing block enforcement for account {event.account_id}"
            )

    def handle_block_expired(self, event: BaseEvent) -> None:
        """Remove MT5 block when expired."""
        if isinstance(event, BlockExpiredEvent):
            self._logger.info(
                f"MT5: Removing expired block for account {event.account_id}"
            )


# ------------------------------------------------------------------
# Factory function for easy setup
# ------------------------------------------------------------------

def create_event_dispatcher() -> EventDispatcher:
    """
    Create and configure an event dispatcher with all subscribers.

    Returns:
        Configured EventDispatcher with Audit, Dashboard, Journal, MT5 subscribers
    """
    dispatcher = EventDispatcher()

    # Create subscribers
    audit_subscriber = AuditLoggerSubscriber()
    dashboard_subscriber = DashboardSubscriber()
    journal_subscriber = JournalSubscriber()
    mt5_subscriber = MT5BlockExecutorSubscriber()

    # Register all handlers
    # Audit Logger
    dispatcher.subscribe(EventType.BLOCK_CREATED, audit_subscriber.handle_block_created)
    dispatcher.subscribe(EventType.BLOCK_RESOLVED, audit_subscriber.handle_block_resolved)
    dispatcher.subscribe(EventType.BLOCK_EXPIRED, audit_subscriber.handle_block_expired)
    dispatcher.subscribe(EventType.RULE_TRIGGERED, audit_subscriber.handle_rule_triggered)

    # Dashboard
    dispatcher.subscribe(EventType.BLOCK_CREATED, dashboard_subscriber.handle_block_created)
    dispatcher.subscribe(EventType.BLOCK_RESOLVED, dashboard_subscriber.handle_block_resolved)
    dispatcher.subscribe(EventType.BLOCK_EXPIRED, dashboard_subscriber.handle_block_expired)
    dispatcher.subscribe(EventType.RULE_TRIGGERED, dashboard_subscriber.handle_rule_triggered)

    # Journal
    dispatcher.subscribe(EventType.BLOCK_CREATED, journal_subscriber.handle_block_created)
    dispatcher.subscribe(EventType.BLOCK_RESOLVED, journal_subscriber.handle_block_resolved)
    dispatcher.subscribe(EventType.RULE_TRIGGERED, journal_subscriber.handle_rule_triggered)

    # MT5 Block Executor
    dispatcher.subscribe(EventType.BLOCK_CREATED, mt5_subscriber.handle_block_created)
    dispatcher.subscribe(EventType.BLOCK_RESOLVED, mt5_subscriber.handle_block_resolved)
    dispatcher.subscribe(EventType.BLOCK_EXPIRED, mt5_subscriber.handle_block_expired)

    return dispatcher


# Global dispatcher instance (optional, for convenience)
_dispatcher: EventDispatcher | None = None


def get_event_dispatcher() -> EventDispatcher:
    """Get the global event dispatcher instance."""
    global _dispatcher
    if _dispatcher is None:
        _dispatcher = create_event_dispatcher()
    return _dispatcher
