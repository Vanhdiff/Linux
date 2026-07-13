# MT5 EA Integration

This folder contains the EA-side contract reference for TradingDesk Block Trade.

## Current Phase D contract

The EA must protect orders using two backend-backed layers:

1. **Pre-trade validation** via local HTTP:
   - `GET /guardrails/pre-trade/contract`
   - `POST /guardrails/pre-trade/validate`
2. **File-based block state sync**:
   - Backend writes `block_{account_id}.json`
   - EA writes `ea_status.json` heartbeat
   - Backend writes `ea_config.json` for runtime EA settings
   - Backend writes `ea_command.json` for one-shot EA commands

## Mandatory fail-safe rule

The EA must only allow a trade when backend response is explicitly valid:

- HTTP status is `200`
- JSON is valid
- all required response fields exist
- `decision == "ALLOW"`
- `allowed == true`

Every other case must deny locally:

- backend down
- timeout
- connection error
- non-200 response
- invalid JSON
- missing required field
- `decision != "ALLOW"`
- `allowed != true`

## EA file

`Experts/TradingDeskGuardEA.mq5` contains a minimal MQL5 implementation skeleton:

- `ValidateBeforeTrade()` calls backend before a trade attempt.
- `PostPreTradeValidation()` uses `WebRequest()` to call `/guardrails/pre-trade/validate`.
- `ShouldAllowBackendResponse()` allows only explicit `ALLOW` + `allowed=true`.
- `WriteHeartbeat()` writes `ea_status.json`.

The backend-owned file contract also includes:

- `ea_config.json`: desired EA runtime settings, including backend URL, account ID, heartbeat interval, enforcement timing, and close/delete policy.
- `ea_command.json`: a pending one-shot command such as `reload_config`, `ping`, or a future repair action. The command remains file-based so the desktop app can automate setup without adding brokers, queues, or external services.

Before testing in MT5, add `http://127.0.0.1:8000` to:

`Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL`

The EA now has two protection modes:

1. **Pre-trade validation for EA-routed orders**: any order-send code must call `ValidateBeforeTrade()` immediately before `OrderSend()` or `CTrade.Buy/Sell()`.
2. **Reactive protection for manual MT5 orders**: `OnTick()` and `OnTradeTransaction()` read `block_{account_id}.json`; when `blocked=true`, the EA attempts to delete pending orders and close open positions.

Important limitation: MT5 EAs cannot prevent a user from clicking Buy/Sell manually before the terminal sends the order. The EA can only react immediately after the position/order appears. True pre-click blocking requires a Windows-level UI overlay/hook or broker/server-side enforcement.
