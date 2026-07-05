# Backend Restructure Plan

## Goal

Build the backend as a trading data platform, not just a thin API layer.

The backend should:

- ingest MT5 data read-only first
- normalize trades, positions, account snapshots, candles, and economic news
- compute analytics consistently
- serve Flutter pages through stable APIs
- keep trade blocking/order execution isolated behind a separate guardrail layer

## Core Principles

- Read-only before write-capable.
- Store normalized data before calculating analytics.
- Keep MT5 integration replaceable.
- Keep external API keys on the backend only.
- Flutter should never know whether data came from MT5, cache, or an online provider.
- Every analytic number should be reproducible from stored raw data.

## Proposed Architecture

```text
Flutter App
  -> Backend API
      -> Auth/User Workspace
      -> Data Ingestion
          -> MT5 Bridge
          -> Economic Calendar Provider
      -> Storage
          -> Raw imports
          -> Normalized trades
          -> Account snapshots
          -> Journal notes/reviews
      -> Analytics Engine
      -> Guardrail Engine
      -> API View Models
```

## Backend Modules

### 1. Identity and Workspace

Purpose:

- support one or many users later
- isolate accounts, broker connections, journals, settings

Entities:

- `users`
- `workspaces`
- `trading_accounts`
- `connections`

### 2. MT5 Ingestion

Phase 1 should be read-only.

Sources:

- Local MT5 script/EA bridge exporting JSON or sending HTTP to backend
- Later: Windows-only Python `MetaTrader5` package

Raw data:

- account snapshot
- open positions
- closed deals
- orders
- symbols
- candles

Important rule:

- Do not calculate final analytics directly from raw MT5 response.
- First normalize raw deals into internal trades.

### 3. Trade Normalization

MT5 deals are not the same thing as trades. A single trade may contain multiple partial closes.

Backend should convert:

```text
MT5 orders/deals -> normalized trades
```

Normalized trade fields:

- account id
- external ticket/order ids
- symbol
- direction
- volume
- open time
- close time
- entry price
- exit price
- stop loss
- take profit
- commission
- swap
- gross pnl
- net pnl
- setup tag
- session
- risk amount
- r multiple
- status

### 4. Journal

Journal should extend normalized trades, not replace them.

Journal data:

- setup
- mistakes
- emotion before entry
- emotion after exit
- followed plan
- screenshot refs
- notes
- review status

### 5. Analytics Engine

Analytics should read normalized trades.

Metrics:

- daily PnL
- weekly/monthly PnL
- win rate
- expectancy
- profit factor
- max drawdown
- average R
- risk per trade
- winrate by setup
- PnL by symbol
- PnL by session: Asia, London, New York
- repeated mistake frequency
- rule break count

### 6. News and Economic Calendar

Primary source for released app:

- backend online economic calendar provider

Optional source:

- MT5 economic calendar bridge

Priority:

```text
MT5 local calendar if connected
Online provider
Cached data
Empty state
```

### 7. Guardrail Engine

This should be separate from analytics.

Read-only guardrails:

- max daily loss reached
- too many trades today
- high-impact news window
- revenge-trading pattern
- risk too high

Write-capable trade blocking should be a later explicit phase.

Trade blocking must not live inside the analytics module.

## Suggested API Surface

### Health

- `GET /health`

### Account

- `GET /accounts`
- `GET /accounts/{account_id}`
- `GET /accounts/{account_id}/snapshot`

### MT5 Ingestion

- `POST /ingest/mt5/snapshot`
- `POST /ingest/mt5/deals`
- `POST /ingest/mt5/positions`
- `GET /connections/mt5/status`

### Trades

- `GET /trades`
- `GET /trades/{trade_id}`
- `PATCH /trades/{trade_id}/journal`
- `POST /trades/sync`

### Journal

- `GET /journal/calendar?month=YYYY-MM`
- `GET /journal/day?date=YYYY-MM-DD`
- `GET /journal/month-summary?month=YYYY-MM`

### Analytics

- `GET /analytics/overview`
- `GET /analytics/daily-pnl`
- `GET /analytics/drawdown`
- `GET /analytics/setups`
- `GET /analytics/sessions`
- `GET /analytics/mistakes`

### News

- `GET /news/calendar`
- `GET /news/upcoming`
- `GET /news/day`

### Guardrails

- `GET /guardrails/status`
- `GET /guardrails/rule-breaks`
- `PATCH /guardrails/settings`

## Storage Recommendation

Development:

- SQLite

Production:

- PostgreSQL

Local cache:

- optional SQLite on the desktop app later

## Recommended Rebuild Order

1. Define database schema.
2. Build ingestion API with sample payloads.
3. Build MT5 local bridge against ingestion API.
4. Normalize deals into trades.
5. Build analytics from normalized trades.
6. Connect Dashboard to analytics APIs.
7. Connect Journal to normalized trades and journal notes.
8. Add economic calendar online provider.
9. Add guardrail read-only checks.
10. Only after all of this, design trade blocking.

## Decisions To Make Before Coding

- Backend language: Python FastAPI or Node/NestJS.
- Storage: SQLite first or PostgreSQL immediately.
- MT5 connection style: local script posts HTTP, JSON file bridge, or Python package.
- Single-user desktop first or multi-user cloud first.
- Whether trade blocking is local-only or cloud-controlled.
