import os
import sqlite3
from pathlib import Path

p = Path(os.environ.get('LOCALAPPDATA', '')) / 'TradingDesk' / 'data' / 'trading_desk.db'
print('DB', p, 'exists=', p.exists())
if not p.exists():
    raise SystemExit(0)

conn = sqlite3.connect(p)
conn.row_factory = sqlite3.Row
queries = {
    'accounts': 'select id,name,login,is_active from trading_accounts order by id desc limit 5',
    'settings': 'select account_id,enabled,max_trades_per_day,settings from guardrail_settings order by account_id desc limit 5',
    'normalized_trades_recent': 'select account_id,id,symbol,direction,opened_at,closed_at,status,volume,net_pnl from normalized_trades order by coalesce(closed_at, opened_at) desc limit 10',
    'raw_deals_recent': 'select account_id,id,deal_id,symbol,deal_time,deal_type,entry,volume,profit from raw_deals order by deal_time desc limit 10',
    'blocks_recent': 'select account_id,id,block_type,triggered_by,blocked_at,expires_at,resolved_at,payload from block_states order by id desc limit 10',
}
for name, sql in queries.items():
    print('\n##', name)
    try:
        rows = list(conn.execute(sql))
        if not rows:
            print('(none)')
        for row in rows:
            print(dict(row))
    except Exception as exc:
        print('ERROR', exc)
