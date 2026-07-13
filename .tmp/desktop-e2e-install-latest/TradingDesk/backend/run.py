import sys
import os
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parent
DEPS_DIR = BACKEND_ROOT / ".deps"

if DEPS_DIR.exists():
    sys.path.insert(0, str(DEPS_DIR))

import uvicorn  # noqa: E402


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=os.environ.get("TRADING_DESK_API_HOST", "127.0.0.1"),
        port=int(os.environ.get("TRADING_DESK_API_PORT", "8000")),
        reload=False,
    )
