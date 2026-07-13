import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'backend' / '.deps'), str(ROOT / 'backend')]

from app.database import SessionLocal
from app.services.guardrail_service import GuardrailService

account_id = 1
with SessionLocal() as db:
    status = GuardrailService(db).status(account_id)
    print('account_id=', status['account_id'])
    print('enabled=', status['enabled'])
    print('mode=', status['mode'])
    print('trade_blocking_enabled=', status['trade_blocking_enabled'])
    print('trade_blocked=', status['trade_blocked'])
    print('status=', status['status'])
    print('summary=', status['summary'])
    print('block_state=', status['block_state'])
    print('guardrail_lock=', status['guardrail_lock'])
    for check in status['checks']:
        if check['rule_code'] in {'too_many_trades_today','max_daily_loss_reached','risk_too_high'}:
            print('check=', check)
