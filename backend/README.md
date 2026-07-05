# Trading Desk Backend

Clean FastAPI backend for the Trading Desk app.

This backend is being rebuilt from the architecture in:

```text
docs/backend_restructure_plan.md
```

## Why FastAPI

FastAPI is a good fit here because:

- Python has the strongest path for MT5 integration and data analysis.
- Pydantic gives strict request/response schemas.
- Analytics can share Python tooling later: pandas, numpy, scipy, statsmodels.
- It is simple to run locally during desktop app development.

## Current Scope

This backend now has the clean project layout, SQLite schema, raw MT5 ingestion,
and the first normalized trade sync path:

```text
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   └── config.py
│   ├── db/
│   │   ├── database.py
│   │   └── models.py
│   ├── api/
│   │   ├── health.py
│   │   ├── accounts.py
│   │   ├── mt5.py
│   │   ├── trades.py
│   │   └── analytics.py
│   ├── services/
│   │   ├── mt5_service.py
│   │   ├── normalization_service.py
│   │   └── analytics_service.py
│   └── schemas/
│       ├── account.py
│       ├── mt5.py
│       └── trade.py
├── data/
├── requirements.txt
└── README.md
```

Analytics now reads from `normalized_trades`, not directly from raw MT5 tables.

## Phase 1 Status

Implemented:

- FastAPI app startup
- SQLite database connection
- SQLAlchemy base models for `trading_accounts` and `trades`
- automatic table creation on startup
- `GET /health`
- `GET /api/accounts`
- `POST /api/accounts`
- `GET /api/accounts/{account_id}`
- Swagger docs at `GET /docs`

## Phase 3 Database Standard

Implemented main tables:

- `trading_accounts`
- `account_snapshots`
- `raw_mt5_imports`
- `raw_deals`
- `raw_orders`
- `raw_positions`
- `normalized_trades`
- `trade_journals`
- `daily_analytics`
- `guardrail_settings`
- `rule_breaks`
- `economic_events`

Additional raw MT5 storage:

- `raw_candles`

Layering rules:

- Raw MT5 payloads are stored in `raw_*` tables.
- Clean trade records live in `normalized_trades`.
- Analytics reads from `normalized_trades`, not directly from raw MT5 data.
- Journal data lives in `trade_journals` and attaches to one normalized trade.

During local development, an old `trades` table may exist if the Phase 1
database was created before Phase 2. It is not used by the new schema and can
be dropped after migrations are formalized with Alembic.

## Phase 5 Raw Data Import

Goal:

- Store original MT5 data in SQLite before any normalization.

MT5 import endpoints:

- `POST /api/mt5/import-raw`
- `POST /api/mt5/sync`

Manual raw ingestion endpoints:

- `POST /ingest/mt5/account-snapshot`
- `POST /ingest/mt5/deals`
- `POST /ingest/mt5/orders`
- `POST /ingest/mt5/positions`
- `POST /ingest/mt5/candles`

These endpoints only validate and store raw data. They do not normalize trades
or calculate analytics.

Flow:

```text
MT5
  -> Python service
  -> raw_deals / raw_orders / raw_positions
  -> raw_mt5_imports
```

## Phase 4 MT5 Connection

Implemented read-only MT5 connection endpoints:

- `GET /api/mt5/status`
- `POST /api/mt5/connect`
- `POST /api/mt5/sync`
- `GET /api/mt5/account`
- `GET /api/mt5/positions`
- `GET /api/mt5/history`

Additional read endpoints:

- `GET /api/mt5/orders`
- `GET /api/mt5/symbols`

Data fetched from the local MT5 terminal:

- account info
- balance
- equity
- positions
- orders
- deals
- symbols

Rules:

- MT5 integration is read-only in this phase.
- `sync` stores source data in raw tables and account snapshots.
- `sync` does not place, modify, or close trades.
- If no `account_id` is provided, `sync` finds or creates a local account by
  MT5 login.

Sample payloads live in:

```text
backend/samples/mt5/
```

Example:

```bash
curl -X POST http://127.0.0.1:8000/ingest/mt5/deals \
  -H 'Content-Type: application/json' \
  -d @backend/samples/mt5/deals.json
```

Flow:

```text
MT5 on Windows
  -> Python bridge or EA bridge
  -> POST JSON to FastAPI
  -> backend stores raw data in SQLite
```

## Phase 6 Normalize Trades

Goal:

- Convert many raw MT5 deal rows into one understandable trade row.

Implemented normalized trade endpoints:

- `POST /api/trades/normalize?account_id=1`
- `POST /api/trades/sync-normalized?account_id=1`
- `GET /api/trades`
- `GET /api/trades?account_id=1`
- `GET /api/trades/{trade_id}`

Flow:

```text
raw_deals many rows
  -> normalized_trades one complete trade
```

The `normalized_trades` table includes user-facing trade fields:

- `id`
- `account_id`
- `symbol`
- `side`
- `volume`
- `open_time`
- `close_time`
- `open_price`
- `close_price`
- `profit`
- `commission`
- `swap`
- `net_profit`
- `duration_seconds`
- `entry_reason`
- `exit_reason`

The normalization service currently:

- reads raw deals for one account
- skips balance/deposit/withdraw/credit operations
- groups deals by MT5 position id when available, otherwise by symbol,
  direction, and trade date
- calculates `entry_price`, `exit_price`, `commission`, `swap`, `gross_pnl`,
  `net_pnl`, estimated `risk_amount`, `r_multiple`, session, and status
- writes clean records to `normalized_trades`
- updates an existing normalized trade when the same source deals are synced
  again

This is the app's source of truth for Dashboard, Journal, and future analytics.
Raw tables are preserved for audit/debugging, but UI analytics should not query
raw deals directly.

Example:

```bash
curl -X POST 'http://127.0.0.1:8000/api/trades/sync-normalized?account_id=1'
curl 'http://127.0.0.1:8000/api/trades?account_id=1'
```

## Phase 6 Journal API

Journal does not replace a trade. A trade comes from `normalized_trades`;
journal only adds user-entered review data:

- setup
- mistakes
- emotion before entry
- emotion after exit
- followed plan
- notes
- screenshot refs
- review status

Implemented journal endpoints:

- `GET /journal/day?date=2026-06-25`
- `GET /journal/calendar?month=2026-06`
- `PATCH /trades/{trade_id}/journal`

The same endpoints are also available under `/api/...`:

- `GET /api/journal/day?date=2026-06-25`
- `GET /api/journal/calendar?month=2026-06`
- `PATCH /api/trades/{trade_id}/journal`

Older full journal endpoints are still available:

- `GET /api/journals`
- `GET /api/journals?account_id=1`
- `GET /api/journals/trades/{trade_id}`
- `PUT /api/journals/trades/{trade_id}`

Journal records are user-owned notes and reviews. They attach to
`normalized_trades.id`, not raw MT5 deal ids.

Example:

```bash
curl -X PATCH http://127.0.0.1:8000/trades/1/journal \
  -H 'Content-Type: application/json' \
  -d '{"setup":"London pullback","mistake":"entered early","emotion_before":"calm","emotion_after":"focused","followed_plan":false,"note":"Reviewed after close.","screenshot":"chart-001.png","review_status":"reviewed"}'
```

## Phase 5 Analytics Engine

Implemented analytics endpoints:

- `GET /analytics/overview`
- `GET /analytics/daily-pnl`
- `GET /analytics/drawdown`
- `GET /analytics/symbols`
- `GET /analytics/sessions`
- `GET /analytics/setups`

The same endpoints are also available under `/api/analytics/...` for the app's
existing API prefix.

The overview currently calculates:

- latest account snapshot
- trade count, wins, losses, breakevens
- win rate
- gross PnL and net PnL
- profit factor
- expectancy
- average R
- max drawdown from the closed trade equity curve
- daily, weekly, and monthly PnL rows
- symbol performance
- session performance
- setup performance, using journal setup first and normalized setup tag second
- repeated mistake counts from journal data

Rules:

- Analytics reads from `normalized_trades`.
- Mistake/setup context may join `trade_journals`.
- Analytics does not read directly from raw MT5 tables.
- Flutter must only call these APIs and display the returned data.

Example:

```bash
curl 'http://127.0.0.1:8000/analytics/overview?account_id=1'
curl 'http://127.0.0.1:8000/analytics/daily-pnl?account_id=1'
curl 'http://127.0.0.1:8000/analytics/drawdown?account_id=1'
curl 'http://127.0.0.1:8000/analytics/symbols?account_id=1'
curl 'http://127.0.0.1:8000/analytics/sessions?account_id=1'
curl 'http://127.0.0.1:8000/analytics/setups?account_id=1'
```

## Phase 6 Dashboard And Journal View Models

Implemented page-level view model endpoints:

- `GET /dashboard?account_id=1`
- `GET /journal/calendar?month=2026-06`
- `GET /journal/day?date=2026-06-25`
- `GET /journal/month-summary?account_id=1&month=2026-06`

The same endpoints are also available under `/api/...`:

- `GET /api/dashboard?account_id=1`
- `GET /api/journal/calendar?month=2026-06`
- `GET /api/journal/day?date=2026-06-25`
- `GET /api/journal/month-summary?account_id=1&month=2026-06`

Purpose:

- Dashboard receives account snapshot, analytics, drawdown, and recent trades in
  one response.
- Journal calendar receives real month days with daily PnL and trade summaries.
- Journal day receives trades plus attached journal notes.
- Journal month summary receives weekly breakdown, symbols, sessions, setups, and
  repeated mistakes scoped to the selected month.

Flutter should call these page APIs instead of calculating page metrics locally.

## Phase 7 News Calendar

Implemented economic calendar cache and API endpoints.

Sources supported by architecture:

- online economic calendar provider posts normalized events to backend
- MT5 economic calendar bridge posts normalized events to backend
- local SQLite cache serves Flutter when no provider is online

Endpoints:

- `POST /ingest/news/events`
- `GET /news/calendar?month=2026-06`
- `GET /news/day?date=2026-06-25`
- `GET /news/upcoming?hours=168`

The read endpoints are also available under `/api/news/...`.

Filters:

- `currencies=USD&currencies=EUR`
- `impacts=high&impacts=medium`

Sample payload:

```text
backend/samples/news/economic_events.json
```

Example:

```bash
curl -X POST http://127.0.0.1:8000/ingest/news/events \
  -H 'Content-Type: application/json' \
  -d @backend/samples/news/economic_events.json

curl 'http://127.0.0.1:8000/news/calendar?month=2026-06'
curl 'http://127.0.0.1:8000/news/day?date=2026-06-25'
curl 'http://127.0.0.1:8000/news/upcoming?hours=168&currencies=USD&impacts=high'
```

Flutter should only read `/news/...` or `/api/news/...`. Provider keys,
scraping logic, MT5 bridge logic, and cache behavior stay in the backend.

## Phase 8 Guardrail Local-Only

Implemented read-only guardrails. This phase does not block trades and does not
send orders to MT5.

Endpoints:

- `GET /guardrails/status?account_id=1`
- `GET /guardrails/status?account_id=1&date=2026-06-25`
- `PATCH /guardrails/settings?account_id=1`
- `GET /guardrails/rule-breaks?account_id=1`

The same endpoints are also available under `/api/guardrails/...`.

Current checks:

- max daily loss reached
- too many trades today
- risk too high
- high-impact news window
- revenge trading pattern
- unresolved rule break count

Data sources:

- `normalized_trades`
- `economic_events`
- `guardrail_settings`
- `rule_breaks`

Example:

```bash
curl -X PATCH 'http://127.0.0.1:8000/guardrails/settings?account_id=1' \
  -H 'Content-Type: application/json' \
  -d '{"max_daily_loss":3000,"max_trades_per_day":5,"max_risk_per_trade":300,"block_high_impact_news":true,"enabled":true}'

curl 'http://127.0.0.1:8000/guardrails/status?account_id=1&date=2026-06-25'
curl 'http://127.0.0.1:8000/guardrails/rule-breaks?account_id=1'
```

`GET /guardrails/status` records currently triggered rules into `rule_breaks`
and resolves them when conditions clear. It still stays local-only: response
field `trade_blocking_enabled` is always `false` in this phase.

## Run Locally

Install dependencies:

```bash
python3 -m pip install -r backend/requirements.txt --target backend/.deps
```

Run:

```bash
python3 -u -c "import sys; sys.path[:0] = ['backend/.deps', 'backend']; import uvicorn; uvicorn.run('app.main:app', host='127.0.0.1', port=8000, log_level='info')"
```

Check:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/api/accounts
curl http://127.0.0.1:8000/docs
```

Create a test account:

```bash
curl -X POST http://127.0.0.1:8000/api/accounts \
  -H 'Content-Type: application/json' \
  -d '{"name":"Demo MT5","broker":"Demo Broker","server":"Demo-MT5","login":"90123456","currency":"USD"}'
```

## Rebuild Order

1. Database schema.
2. MT5 ingestion payload contracts.
3. Raw import storage.
4. Trade normalization.
5. Journal notes and reviews.
6. Analytics engine from normalized trades.
7. Dashboard and Journal API view models.
8. News provider.
9. Read-only guardrails.
10. Trade blocking as a separate later phase.
