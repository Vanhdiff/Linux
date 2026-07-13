# MT5 Real Demo Validation Checklist

Use this checklist for a live MetaTrader 5 demo session with the backend and `TradingDeskGuardEA`.

## Preconditions

- EA is installed in the target terminal.
- EA compiles successfully in MetaEditor.
- MT5 allows WebRequest to the backend base URL.
- Backend and EA point to the same `FILE_COMMON` directory.
- `ea_status.json` is updating with a fresh heartbeat.
- `block_<account_id>.json` is writable by the backend.
- `backend_mt5_demo_audit.jsonl` and `ea_mt5_demo_audit.jsonl` are being created in the shared directory.

## What To Measure

Capture these timestamps from the structured timing audit:

- `rule_detected_at`
- `block_persisted_at`
- `block_file_written_at`
- `ea_transaction_received_at`
- `close_request_sent_at`
- `close_confirmed_at`

## Timing Interpretation

- Backend reaction target: under `500ms`
  - Measure from `rule_detected_at` to `block_file_written_at`
- Do not claim broker execution under `500ms` unless both of these are measured:
  - `close_request_sent_at`
  - `close_confirmed_at`

## Recommended Live Run

1. Start backend.
2. Start MT5 and attach `TradingDeskGuardEA`.
3. Confirm `/mt5/ea/status` shows a fresh heartbeat.
4. Trigger a guardrail block condition on the demo account.
5. Open `/mt5/demo-harness/report?account_id=<id>`.
6. Review checklist completion and timing audit fields.
7. Record backend reaction timing separately from broker execution timing.
