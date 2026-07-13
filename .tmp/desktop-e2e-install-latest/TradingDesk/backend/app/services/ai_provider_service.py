from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any

from app.config import settings


class AiProviderService:
    """Optional AI writer for AI Coach only.

    Trading metrics stay deterministic in AiCoachService. This provider only
    turns the prepared context into coaching language and must return the same
    JSON shape as the local review.
    """

    def is_enabled(self) -> bool:
        return bool(settings.ai_coach_enabled and settings.ai_api_key)

    def coach_review(
        self,
        context: dict[str, Any],
        local_review: dict[str, Any],
        language: str,
    ) -> dict[str, Any] | None:
        if not self.is_enabled():
            return None

        payload = self._payload(context, local_review, language)
        request = urllib.request.Request(
            f"{settings.ai_base_url.rstrip('/')}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {settings.ai_api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(
                request,
                timeout=max(5, settings.ai_timeout_seconds),
            ) as response:
                raw = response.read().decode("utf-8")
        except (urllib.error.URLError, TimeoutError, OSError):
            return None

        try:
            data = json.loads(raw)
            content = data["choices"][0]["message"]["content"]
            review = self._parse_json_object(content)
        except (KeyError, IndexError, TypeError, json.JSONDecodeError):
            return None

        return self._validated_review(review, local_review, language)

    def _payload(
        self,
        context: dict[str, Any],
        local_review: dict[str, Any],
        language: str,
    ) -> dict[str, Any]:
        output_language = "Vietnamese" if language == "vi" else "English"
        prompt = {
            "role": "system",
            "content": (
                "You are a trading discipline coach inside a desktop trading journal. "
                "Use only the provided facts. Do not invent trades, prices, profits, "
                "or economic events. Do not promise profit or give financial advice. "
                "Write concise, practical coaching for the next session. "
                f"Respond in {output_language}. Return JSON only with this schema: "
                '{"headline": string, "risk_level": "low|medium|high|neutral", '
                '"key_findings": string[], "advice": string[], '
                '"next_session_plan": {"max_trades": number|string, '
                '"risk_per_trade": string, "focus": string, "avoid": string[]}}.'
            ),
        }
        user = {
            "role": "user",
            "content": json.dumps(
                {
                    "context": self._compact_context(context),
                    "local_review": local_review,
                },
                ensure_ascii=False,
            ),
        }
        return {
            "model": settings.ai_model,
            "messages": [prompt, user],
            "temperature": 0.3,
        }

    def _compact_context(self, context: dict[str, Any]) -> dict[str, Any]:
        allowed_keys = [
            "period",
            "start_date",
            "end_date",
            "summary",
            "previous_summary",
            "guardrails",
            "rule_breaks",
            "mistakes",
            "symbols",
            "sessions",
            "setups",
            "top_losses",
            "top_wins",
            "economic_events",
            "recent_notes",
        ]
        compact = {key: context.get(key) for key in allowed_keys}
        for key in ["symbols", "sessions", "setups", "top_losses", "top_wins"]:
            if isinstance(compact.get(key), list):
                compact[key] = compact[key][:5]
        for key in ["mistakes", "rule_breaks", "economic_events", "recent_notes"]:
            if isinstance(compact.get(key), list):
                compact[key] = compact[key][:8]
        return compact

    def _parse_json_object(self, content: str) -> dict[str, Any]:
        stripped = content.strip()
        if stripped.startswith("```"):
            stripped = stripped.strip("`")
            if stripped.startswith("json"):
                stripped = stripped[4:].strip()
        start = stripped.find("{")
        end = stripped.rfind("}")
        if start >= 0 and end > start:
            stripped = stripped[start : end + 1]
        return json.loads(stripped)

    def _validated_review(
        self,
        review: dict[str, Any],
        fallback: dict[str, Any],
        language: str,
    ) -> dict[str, Any]:
        risk_level = str(review.get("risk_level") or fallback.get("risk_level") or "neutral")
        if risk_level not in {"low", "medium", "high", "neutral"}:
            risk_level = "neutral"

        next_plan = review.get("next_session_plan")
        if not isinstance(next_plan, dict):
            next_plan = fallback.get("next_session_plan") or {}
        avoid = next_plan.get("avoid")
        if isinstance(avoid, str):
            avoid = [avoid] if avoid.strip() else []
        if not isinstance(avoid, list):
            avoid = []

        return {
            "headline": str(review.get("headline") or fallback.get("headline") or ""),
            "risk_level": risk_level,
            "key_findings": self._string_list(
                review.get("key_findings"),
                fallback.get("key_findings"),
            ),
            "advice": self._string_list(review.get("advice"), fallback.get("advice")),
            "next_session_plan": {
                "max_trades": next_plan.get("max_trades", "-"),
                "risk_per_trade": str(next_plan.get("risk_per_trade", "-")),
                "focus": str(next_plan.get("focus", "-")),
                "avoid": [str(item) for item in avoid[:5]],
            },
            "source": "ai",
            "language": language,
        }

    def _string_list(self, value: Any, fallback: Any) -> list[str]:
        source = value if isinstance(value, list) and value else fallback
        if not isinstance(source, list):
            return []
        return [str(item) for item in source if str(item).strip()][:5]
