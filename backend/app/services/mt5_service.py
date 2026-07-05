from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Any

from app.schemas.mt5 import Mt5ConnectRequest, Mt5ConnectionStatus


class Mt5Service:
    def _load_mt5(self):
        try:
            import MetaTrader5 as mt5
        except ImportError as exc:
            raise RuntimeError("MetaTrader5 Python package is not installed.") from exc

        return mt5

    @contextmanager
    def connection(
        self,
        payload: Mt5ConnectRequest | None = None,
    ) -> Iterator[Any]:
        mt5 = self._load_mt5()
        init_kwargs = self._init_kwargs(payload)
        initialized = mt5.initialize(**init_kwargs)
        if not initialized:
            raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")

        try:
            yield mt5
        finally:
            mt5.shutdown()

    def status(self) -> Mt5ConnectionStatus:
        mt5 = self._load_mt5()
        initialized = mt5.initialize()
        error = mt5.last_error()
        if initialized:
            mt5.shutdown()

        return Mt5ConnectionStatus(
            connected=initialized,
            mode="read_only",
            message="Connected to MT5 terminal." if initialized else f"MT5 initialize failed: {error}",
        )

    def connect(self, payload: Mt5ConnectRequest | None = None) -> dict[str, Any]:
        with self.connection(payload) as mt5:
            return {
                "connected": True,
                "mode": "read_only",
                "message": "Connected to MT5 terminal.",
                "account_info": self._required_info(mt5.account_info(), mt5, "account_info"),
                "terminal_info": self._optional_info(mt5.terminal_info()),
            }

    def account_info(self) -> dict[str, Any]:
        return self.account()

    def account(self, payload: Mt5ConnectRequest | None = None) -> dict[str, Any]:
        with self.connection(payload) as mt5:
            return self._required_info(mt5.account_info(), mt5, "account_info")

    def positions(self, payload: Mt5ConnectRequest | None = None) -> list[dict[str, Any]]:
        with self.connection(payload) as mt5:
            return [
                self._normalize_position(item)
                for item in self._optional_sequence(mt5.positions_get())
            ]

    def floating_pnl(self, payload: Mt5ConnectRequest | None = None) -> float:
        positions = self.positions(payload)
        return round(
            sum(float(position.get("profit") or 0) for position in positions),
            2,
        )

    def orders(self, payload: Mt5ConnectRequest | None = None) -> list[dict[str, Any]]:
        with self.connection(payload) as mt5:
            return [
                self._normalize_order(item)
                for item in self._optional_sequence(mt5.orders_get())
            ]

    def history(
        self,
        *,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        history_days: int = 30,
        payload: Mt5ConnectRequest | None = None,
    ) -> list[dict[str, Any]]:
        start, end = self._history_window(date_from, date_to, history_days)
        with self.connection(payload) as mt5:
            deals = mt5.history_deals_get(start, end)
            if deals is None:
                error = mt5.last_error()
                if error and error[0] not in (1,):
                    raise RuntimeError(f"MT5 history_deals_get failed: {error}")
                return []
            return [self._normalize_deal(item) for item in deals]

    def symbols(
        self,
        group: str | None = None,
        limit: int | None = 200,
        payload: Mt5ConnectRequest | None = None,
    ) -> list[dict[str, Any]]:
        with self.connection(payload) as mt5:
            symbols = mt5.symbols_get(group) if group else mt5.symbols_get()
            rows = [self._to_dict(item) for item in self._optional_sequence(symbols)]
            return rows[:limit] if limit is not None else rows

    def market_snapshot(
        self,
        *,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        history_days: int = 30,
        payload: Mt5ConnectRequest | None = None,
    ) -> dict[str, Any]:
        start, end = self._history_window(date_from, date_to, history_days)
        with self.connection(payload) as mt5:
            return {
                "account_info": self._required_info(mt5.account_info(), mt5, "account_info"),
                "positions": [
                    self._normalize_position(item)
                    for item in self._optional_sequence(mt5.positions_get())
                ],
                "orders": [
                    self._normalize_order(item)
                    for item in self._optional_sequence(mt5.orders_get())
                ],
                "deals": [
                    self._normalize_deal(item)
                    for item in self._optional_sequence(mt5.history_deals_get(start, end))
                ],
                "date_from": start,
                "date_to": end,
            }

    def enforce_trade_block(
        self,
        *,
        blocked_since: datetime,
        payload: Mt5ConnectRequest | None = None,
    ) -> dict[str, Any]:
        with self.connection(payload) as mt5:
            pending_orders = self._optional_sequence(mt5.orders_get())
            positions = self._optional_sequence(mt5.positions_get())

            deleted_orders = []
            closed_positions = []
            failed_actions = []

            for order in pending_orders:
                result = self._remove_order(mt5, order)
                action = {
                    "order": getattr(order, "ticket", None),
                    "symbol": getattr(order, "symbol", None),
                    "result": result,
                }
                if self._trade_result_ok(mt5, result):
                    deleted_orders.append(action)
                else:
                    failed_actions.append({"action": "delete_order", **action})

            for position in positions:
                opened_at = int(getattr(position, "time", 0) or 0)
                result = self._close_position(mt5, position)
                action = {
                    "position": getattr(position, "ticket", None),
                    "symbol": getattr(position, "symbol", None),
                    "opened_at": opened_at,
                    "result": result,
                }
                if self._trade_result_ok(mt5, result):
                    closed_positions.append(action)
                else:
                    failed_actions.append({"action": "close_position", **action})

            return {
                "blocked_since": blocked_since.isoformat(),
                "mode": "strict_close_all",
                "deleted_orders": deleted_orders,
                "closed_positions": closed_positions,
                "failed_actions": failed_actions,
            }

    def _init_kwargs(self, payload: Mt5ConnectRequest | None) -> dict[str, Any]:
        if payload is None:
            return {}
        values = payload.model_dump(
            include={"path", "login", "password", "server", "timeout", "portable"},
            exclude_none=True,
        )
        return values

    def _history_window(
        self,
        date_from: datetime | None,
        date_to: datetime | None,
        history_days: int,
    ) -> tuple[datetime, datetime]:
        # MT5 history timestamps often follow broker/server time rather than
        # local UTC. A one-day forward buffer prevents same-day closed trades
        # from being missed when the broker server is ahead of this machine.
        end = date_to or (datetime.now(timezone.utc) + timedelta(days=1))
        start = date_from or (end - timedelta(days=history_days))
        return start, end

    def _optional_info(self, value: Any) -> dict[str, Any] | None:
        return None if value is None else self._to_dict(value)

    def _required_info(self, value: Any, mt5: Any, name: str) -> dict[str, Any]:
        if value is None:
            raise RuntimeError(f"MT5 {name} failed: {mt5.last_error()}")
        return self._to_dict(value)

    def _optional_sequence(self, value: Any) -> list[Any]:
        if value is None:
            return []
        return list(value)

    def _normalize_position(self, item: Any) -> dict[str, Any]:
        row = self._to_dict(item)
        row["external_position_id"] = str(row.get("ticket") or row.get("identifier") or "")
        row["direction"] = self._direction(row.get("type"))
        row["open_price"] = row.get("price_open")
        row["current_price"] = row.get("price_current")
        row["stop_loss"] = row.get("sl")
        row["take_profit"] = row.get("tp")
        row["opened_at"] = row.get("time")
        return row

    def _normalize_order(self, item: Any) -> dict[str, Any]:
        row = self._to_dict(item)
        row["external_order_id"] = str(row.get("ticket") or row.get("order") or "")
        row["order_type"] = self._order_type(row.get("type"))
        row["order_time"] = row.get("time_setup") or row.get("time")
        row["stop_loss"] = row.get("sl")
        row["take_profit"] = row.get("tp")
        return row

    def _normalize_deal(self, item: Any) -> dict[str, Any]:
        row = self._to_dict(item)
        row["external_deal_id"] = str(row.get("ticket") or row.get("deal") or "")
        row["external_order_id"] = str(row.get("order") or "")
        row["direction"] = self._direction(row.get("type"))
        row["entry_type"] = self._entry_type(row.get("entry"))
        return row

    def _to_dict(self, item: Any) -> dict[str, Any]:
        if isinstance(item, dict):
            source = item
        elif hasattr(item, "_asdict"):
            source = item._asdict()
        else:
            source = {
                key: getattr(item, key)
                for key in dir(item)
                if not key.startswith("_") and not callable(getattr(item, key))
            }
        return {key: self._json_value(value) for key, value in source.items()}

    def _json_value(self, value: Any) -> Any:
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, bytes):
            return value.decode(errors="ignore")
        if isinstance(value, tuple):
            return [self._json_value(item) for item in value]
        if isinstance(value, list):
            return [self._json_value(item) for item in value]
        if isinstance(value, dict):
            return {key: self._json_value(item) for key, item in value.items()}
        return value

    def _direction(self, value: Any) -> str:
        return "sell" if value == 1 else "buy"

    def _entry_type(self, value: Any) -> str:
        return {
            0: "in",
            1: "out",
            2: "inout",
            3: "out_by",
        }.get(value, str(value or ""))

    def _order_type(self, value: Any) -> str:
        return {
            0: "buy",
            1: "sell",
            2: "buy_limit",
            3: "sell_limit",
            4: "buy_stop",
            5: "sell_stop",
            6: "buy_stop_limit",
            7: "sell_stop_limit",
        }.get(value, str(value or ""))

    def _remove_order(self, mt5: Any, order: Any) -> dict[str, Any]:
        request = {
            "action": mt5.TRADE_ACTION_REMOVE,
            "order": getattr(order, "ticket", None),
            "comment": "TradingDesk guardrail block",
        }
        return self._trade_result(mt5.order_send(request))

    def _close_position(self, mt5: Any, position: Any) -> dict[str, Any]:
        symbol = getattr(position, "symbol", "")
        volume = float(getattr(position, "volume", 0) or 0)
        position_type = getattr(position, "type", None)
        ticket = getattr(position, "ticket", None)
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            return {
                "retcode": None,
                "comment": f"No tick data for {symbol}",
                "ok": False,
            }

        is_buy = position_type == getattr(mt5, "POSITION_TYPE_BUY", 0)
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "position": ticket,
            "symbol": symbol,
            "volume": volume,
            "type": mt5.ORDER_TYPE_SELL if is_buy else mt5.ORDER_TYPE_BUY,
            "price": tick.bid if is_buy else tick.ask,
            "deviation": 30,
            "magic": 20260629,
            "comment": "TradingDesk guardrail block",
            "type_time": mt5.ORDER_TIME_GTC,
        }
        return self._send_with_filling_fallback(mt5, request)

    def _send_with_filling_fallback(
        self,
        mt5: Any,
        request: dict[str, Any],
    ) -> dict[str, Any]:
        filling_modes = [
            getattr(mt5, "ORDER_FILLING_IOC", None),
            getattr(mt5, "ORDER_FILLING_FOK", None),
            getattr(mt5, "ORDER_FILLING_RETURN", None),
            None,
        ]
        last_result: dict[str, Any] = {
            "retcode": None,
            "comment": "No MT5 filling modes attempted",
        }
        for filling_mode in dict.fromkeys(filling_modes):
            current_request = dict(request)
            if filling_mode is not None:
                current_request["type_filling"] = filling_mode
            result = self._trade_result(mt5.order_send(current_request))
            result["attempted_filling"] = filling_mode
            last_result = result
            if self._trade_result_ok(mt5, result):
                return result
        return last_result

    def _trade_result(self, result: Any) -> dict[str, Any]:
        if result is None:
            return {"retcode": None, "comment": "MT5 order_send returned None"}
        return self._to_dict(result)

    def _trade_result_ok(self, mt5: Any, result: dict[str, Any]) -> bool:
        ok_codes = {
            getattr(mt5, "TRADE_RETCODE_DONE", 10009),
            getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010),
            getattr(mt5, "TRADE_RETCODE_PLACED", 10008),
        }
        return result.get("retcode") in ok_codes

