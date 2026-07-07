# Application layer for Block Trade feature
from app.application.block_decision_engine import BlockDecisionEngine
from app.application.block_executor import BlockExecutor, BlockEvent, ExecutionResult
from app.application.event_dispatcher import (
    EventDispatcher,
    EventType,
    BaseEvent,
    BlockCreatedEvent,
    BlockResolvedEvent,
    BlockExpiredEvent,
    RuleTriggeredEvent,
    get_event_dispatcher,
    create_event_dispatcher,
)
from app.application.mt5_protection import (
    MT5BlockEnforcer,
    EACommunicationLayer,
    BlockStateSync,
    EAStatus,
)

__all__ = [
    "BlockDecisionEngine",
    "BlockExecutor",
    "BlockEvent",
    "ExecutionResult",
    # Event Dispatcher
    "EventDispatcher",
    "EventType",
    "BaseEvent",
    "BlockCreatedEvent",
    "BlockResolvedEvent",
    "BlockExpiredEvent",
    "RuleTriggeredEvent",
    "get_event_dispatcher",
    "create_event_dispatcher",
    # MT5 Protection
    "MT5BlockEnforcer",
    "EACommunicationLayer",
    "BlockStateSync",
    "EAStatus",
]
