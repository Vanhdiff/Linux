# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Trading Desktop App for managing, analyzing, and enforcing trading discipline. It connects to MT5 (MetaTrader 5), stores trade history, analyzes performance, and provides journaling capabilities.

## Development Commands

### Flutter Desktop App
```bash
# Run the app
flutter run -d windows

# Run with specific device
flutter run -d <device-id>

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze code
flutter analyze

# Build for Windows
flutter build windows
```

### Backend (FastAPI)
```bash
# Navigate to backend directory
cd backend

# Run the backend server
python run.py

# The API will be available at http://127.0.0.1:8000
# API docs at http://127.0.0.1:8000/docs
```

### Environment Variables
- `TRADING_DESK_API_HOST` - Backend host (default: 127.0.0.1)
- `TRADING_DESK_API_PORT` - Backend port (default: 8000)

## Architecture

### Flutter Frontend (Clean Architecture)

```
lib/
├── app/                    # App-level setup
│   ├── router/            # Navigation routes
│   ├── services/          # API clients, storage, MT5 integration
│   ├── shell/             # Main shell with sidebar navigation
│   └── state/            # Global app state
├── core/                  # Shared utilities
│   ├── constants/        # App constants, storage keys
│   ├── enums/           # TradeDirection, TradeOutcome, etc.
│   ├── errors/          # Result type, Failure handling
│   ├── extensions/      # Dart extensions
│   └── utils/           # Formatters, validators, calculations
└── features/            # Feature modules (clean architecture)
    └── [feature]/
        ├── data/        # DTOs, datasources, repository implementations
        ├── domain/      # Entities, repository interfaces, use cases
        └── presentation/# Pages, widgets, controllers
```

**Key Features:**
- `auth` - Login/logout, session management
- `dashboard` - Main trading dashboard with metrics and charts
- `journal` - Trade journaling with reviews
- `guardrails` - Risk management rules
- `notebook` - Trading notes and templates
- `news` - Economic news calendar
- `ai_coach` - AI-powered trading assistant
- `plan` - Trading plans
- `settings` - App configuration

### Backend (FastAPI)

```
backend/
├── app/
│   ├── api/              # API route handlers
│   ├── models/           # SQLAlchemy ORM models
│   ├── schemas/          # Pydantic request/response schemas
│   ├── services/         # Business logic (analytics, guardrails, etc.)
│   ├── config.py         # Settings with pydantic-settings
│   └── database.py       # SQLite/SQLAlchemy setup
└── run.py                # Entry point (uvicorn)
```

**Key API Routes:**
- `/health` - Health check
- `/api/accounts` - Account management
- `/api/trades` - Trade data
- `/api/analytics` - Performance analytics
- `/api/guardrails` - Rule enforcement
- `/api/journal` - Trade journaling
- `/api/notebook` - Notes management
- `/api/mt5` - MT5 synchronization

### Data Flow
1. MT5 exports data → Backend ingestion service normalizes it
2. Backend stores: raw data (unmodified) + normalized trades
3. Analytics computed from normalized data only
4. Flutter frontend consumes REST API + WebSocket for real-time updates

## Important Patterns

### Flutter: Domain-Driven Structure
Each feature follows the clean architecture pattern:
- `domain/` - Pure business logic, no Flutter dependencies
- `data/` - API calls, local storage, mapping to/from domain
- `presentation/` - UI widgets and pages

### Backend: Separation of Concerns
- Routes only handle HTTP, delegate to services
- Services contain business logic
- Models are for database, schemas for API validation

### License System
- Online license checking at startup
- Exempt paths: `/health`, `/docs`, `/license` endpoints
- MT5 trade blocker only active when license is valid

## Key Files
- [AGENT.md](AGENT.md) - Vietnamese development rules and conventions (read first)
- [pubspec.yaml](pubspec.yaml) - Flutter dependencies
- [backend/requirements.txt](backend/requirements.txt) - Python dependencies
