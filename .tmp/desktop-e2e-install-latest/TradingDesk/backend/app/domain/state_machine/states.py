"""
Explicit state definitions for Block State Machine.

Defines the valid states and transitions for the block lifecycle.
"""
from enum import Enum


class BlockStateEnum(str, Enum):
    """
    Explicit states for block state machine.

    NORMAL - No active block, trading allowed
    WARNING - Rules triggered but not blocking yet
    TEMPORARY_BLOCK - Blocked for a duration (e.g., 60 minutes)
    FULL_DAY_BLOCK - Blocked until next trading day
    RESOLVED - Block ended and has not yet been archived
    ARCHIVED - Historical record no longer active
    """
    NORMAL = "NORMAL"
    WARNING = "WARNING"
    TEMPORARY_BLOCK = "TEMPORARY_BLOCK"
    FULL_DAY_BLOCK = "FULL_DAY_BLOCK"
    RESOLVED = "RESOLVED"
    ARCHIVED = "ARCHIVED"


# Valid state transitions
# Maps from_state -> set of valid to_states
VALID_TRANSITIONS = {
    BlockStateEnum.NORMAL: {
        BlockStateEnum.WARNING,
        BlockStateEnum.TEMPORARY_BLOCK,
        BlockStateEnum.FULL_DAY_BLOCK,
        BlockStateEnum.RESOLVED,
        BlockStateEnum.ARCHIVED,
    },
    BlockStateEnum.WARNING: {
        BlockStateEnum.TEMPORARY_BLOCK,
        BlockStateEnum.FULL_DAY_BLOCK,
        BlockStateEnum.NORMAL,
        BlockStateEnum.RESOLVED,
        BlockStateEnum.ARCHIVED,
    },
    BlockStateEnum.TEMPORARY_BLOCK: {
        BlockStateEnum.FULL_DAY_BLOCK,  # Upgrade
        BlockStateEnum.RESOLVED,  # Expiry
        BlockStateEnum.ARCHIVED,
    },
    BlockStateEnum.FULL_DAY_BLOCK: {
        BlockStateEnum.RESOLVED,  # Next day reset
        BlockStateEnum.ARCHIVED,
    },
    BlockStateEnum.RESOLVED: {
        BlockStateEnum.NORMAL,
        BlockStateEnum.ARCHIVED,
    },
    BlockStateEnum.ARCHIVED: {
        BlockStateEnum.NORMAL,
    },
}


def is_valid_transition(from_state: BlockStateEnum, to_state: BlockStateEnum) -> bool:
    """Check if transition from one state to another is valid."""
    if from_state == to_state:
        return True  # Staying in same state is always valid
    return to_state in VALID_TRANSITIONS.get(from_state, set())


def get_blocking_states() -> set[BlockStateEnum]:
    """Return states where trading is blocked."""
    return {
        BlockStateEnum.TEMPORARY_BLOCK,
        BlockStateEnum.FULL_DAY_BLOCK,
    }


def is_blocking_state(state: BlockStateEnum) -> bool:
    """Check if a state blocks trading."""
    return state in get_blocking_states()


def is_terminal_state(state: BlockStateEnum) -> bool:
    """Check if a state is terminal for active block handling."""
    return state in {BlockStateEnum.RESOLVED, BlockStateEnum.ARCHIVED}
