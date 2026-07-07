# TradingApp Desktop

## Project Goal

Trading discipline desktop application for MT5 traders.

Main objectives:

- Trading analytics
- Journal
- Discipline scoring
- Rule engine
- Block Trade
- MT5 integration

Current stack:

Frontend
- Flutter Desktop

Backend
- FastAPI

Database
- SQLite

Trading Platform
- MT5

Current architecture:
Modular Monolith

NOT microservice.

---

## Current Block Trade Status

Existing:

- Rule Engine
- Guardrail Service
- Block State
- Dashboard Banner
- Countdown
- Settings Lock
- Database persistence
- MT5 polling

Reviewed:

Two architecture reviews completed.

Current conclusion:

Block Trade backend works but architecture needs refactoring before adding more features.

Major missing parts:

- Windows Guard
- Proper Domain Layer
- State Machine
- Block Executor
- Event Dispatcher
- Recovery improvements
- MT5 EA communication

---

## Target Architecture

Rule Engine

↓

Decision Engine

↓

Block Executor

↓

Event Dispatcher

↓

Subscribers

- Dashboard
- Journal
- Audit
- MT5
- Windows Guard

---

Current priority:

Finish backend architecture first.

Do NOT implement Windows Guard yet.

Do NOT redesign the whole project.

Keep Modular Monolith.