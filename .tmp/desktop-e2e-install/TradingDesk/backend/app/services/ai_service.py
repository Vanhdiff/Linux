from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from typing import Any

from sqlalchemy.orm import Session

from app.models import (
    AccountSnapshot,
    AiChatUsage,
    EconomicEvent,
    License,
    NormalizedTrade,
    NotebookNote,
    RuleBreak,
)
from app.services.ai_provider_service import AiProviderService
from app.services.guardrail_service import GuardrailService


class AiCoachService:
    """Builds compact, factual coaching summaries from local trading data."""

    DAILY_CHAT_LIMIT = 5

    def __init__(self, db: Session) -> None:
        self._db = db

    def context(
        self,
        account_id: int | None,
        period: str = "day",
        target_date: date | None = None,
    ) -> dict[str, Any]:
        target = target_date or self._today()
        start, end = self._period_bounds(period, target)
        trades = self._closed_trades(account_id, start, end)
        previous_trades = self._closed_trades(
            account_id,
            start - (end - start) - timedelta(days=1),
            start - timedelta(days=1),
        )
        summary = self._summary(trades)
        previous_summary = self._summary(previous_trades)
        rule_breaks = self._rule_breaks(account_id, start, end)
        events = self._events(start, end)
        notes = self._recent_notes(account_id)

        return {
            "account_id": account_id,
            "period": period,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "summary": summary,
            "previous_summary": previous_summary,
            "guardrails": self._guardrail_payload(account_id, target),
            "rule_breaks": self._rule_break_payload(rule_breaks),
            "mistakes": self._mistake_payload(trades),
            "symbols": self._group_payload(trades, lambda trade: trade.symbol or "Unknown"),
            "sessions": self._group_payload(
                trades,
                lambda trade: trade.session or "Unknown",
            ),
            "setups": self._group_payload(
                trades,
                lambda trade: (
                    trade.journal.setup
                    if trade.journal and trade.journal.setup
                    else trade.setup_tag or "Unlabeled"
                ),
            ),
            "top_losses": [self._trade_payload(trade) for trade in self._top_losses(trades)],
            "top_wins": [self._trade_payload(trade) for trade in self._top_wins(trades)],
            "economic_events": [self._event_payload(event) for event in events],
            "recent_notes": [self._note_payload(note) for note in notes],
        }

    def daily_review(
        self,
        account_id: int | None,
        target_date: date | None = None,
        language: str = "en",
    ) -> dict[str, Any]:
        context = self.context(account_id, period="day", target_date=target_date)
        return {
            "context": context,
            "review": self._coach_review_with_ai(context, language),
        }

    def weekly_review(
        self,
        account_id: int | None,
        target_date: date | None = None,
        language: str = "en",
    ) -> dict[str, Any]:
        context = self.context(account_id, period="week", target_date=target_date)
        return {
            "context": context,
            "review": self._coach_review_with_ai(context, language),
        }

    def monthly_review(
        self,
        account_id: int | None,
        target_date: date | None = None,
        language: str = "en",
    ) -> dict[str, Any]:
        context = self.context(account_id, period="month", target_date=target_date)
        return {
            "context": context,
            "review": self._coach_review_with_ai(context, language),
        }

    def trade_review(
        self,
        account_id: int | None,
        trade_id: int,
        language: str = "en",
    ) -> dict[str, Any]:
        query = self._db.query(NormalizedTrade).filter(NormalizedTrade.id == trade_id)
        if account_id is not None:
            query = query.filter(NormalizedTrade.account_id == account_id)
        trade = query.one_or_none()
        if trade is None:
            return {
                "trade": None,
                "review": {
                    "headline": "Trade not found",
                    "risk_level": "unknown",
                    "key_findings": ["No normalized trade exists for this id."],
                    "advice": ["Sync MT5 again, then reopen this trade review."],
                    "next_session_plan": {},
                },
            }
        context = {
            "period": "trade",
            "summary": self._summary([trade]),
            "top_losses": [self._trade_payload(trade)] if trade.net_pnl < 0 else [],
            "top_wins": [self._trade_payload(trade)] if trade.net_pnl > 0 else [],
            "mistakes": self._mistake_payload([trade]),
            "rule_breaks": self._rule_break_payload(trade.rule_breaks),
            "symbols": self._group_payload([trade], lambda item: item.symbol or "Unknown"),
            "sessions": self._group_payload([trade], lambda item: item.session or "Unknown"),
            "setups": self._group_payload(
                [trade],
                lambda item: (
                    item.journal.setup
                    if item.journal and item.journal.setup
                    else item.setup_tag or "Unlabeled"
                ),
            ),
        }
        return {
            "trade": self._trade_payload(trade),
            "review": self._coach_review_with_ai(context, language),
        }

    def chat(
        self,
        account_id: int | None,
        question: str,
        language: str = "en",
    ) -> dict[str, Any]:
        cleaned_question = " ".join(question.strip().split())
        if not cleaned_question:
            return {
                "answer": "Please ask a trading-related question.",
                "remaining": self.DAILY_CHAT_LIMIT,
                "limit": self.DAILY_CHAT_LIMIT,
                "source": "local",
            }
        if len(cleaned_question) > 900:
            cleaned_question = cleaned_question[:900]

        usage = self._consume_chat_quota()
        if not usage["allowed"]:
            return {
                "answer": self._localized(
                    language,
                    "You have used all 5 AI Coach questions for today. Come back tomorrow or use the fixed review panels.",
                    "Bạn đã dùng hết 5 câu hỏi AI Coach hôm nay. Hãy quay lại ngày mai hoặc dùng các phần review cố định.",
                ),
                "remaining": 0,
                "limit": self.DAILY_CHAT_LIMIT,
                "source": "quota",
            }

        context = self.context(account_id, period="month")
        review = self._coach_review(context)
        answer = self._local_chat_answer(cleaned_question, context, review, language)
        return {
            "answer": answer,
            "remaining": usage["remaining"],
            "limit": self.DAILY_CHAT_LIMIT,
            "source": "local",
            "context_period": "month",
        }

    def _consume_chat_quota(self) -> dict[str, Any]:
        today = self._today()
        license_record = self._db.query(License).order_by(License.id.asc()).first()
        license_key = license_record.license_key if license_record else "local"
        usage = (
            self._db.query(AiChatUsage)
            .filter(
                AiChatUsage.license_key == license_key,
                AiChatUsage.usage_date == today,
            )
            .one_or_none()
        )
        if usage is None:
            usage = AiChatUsage(
                license_key=license_key,
                usage_date=today,
                question_count=0,
            )
            self._db.add(usage)
            self._db.flush()

        if usage.question_count >= self.DAILY_CHAT_LIMIT:
            return {"allowed": False, "remaining": 0}

        usage.question_count += 1
        self._db.commit()
        return {
            "allowed": True,
            "remaining": max(self.DAILY_CHAT_LIMIT - usage.question_count, 0),
        }

    def _local_chat_answer(
        self,
        question: str,
        context: dict[str, Any],
        review: dict[str, Any],
        language: str,
    ) -> str:
        summary = context["summary"]
        symbols = context.get("symbols", [])
        sessions = context.get("sessions", [])
        mistakes = context.get("mistakes", [])
        rule_breaks = context.get("rule_breaks", [])
        top_losses = context.get("top_losses", [])
        top_wins = context.get("top_wins", [])
        q = question.lower()

        weakest_symbol = min(symbols, key=lambda item: item["net_pnl"], default=None)
        weakest_session = min(sessions, key=lambda item: item["net_pnl"], default=None)
        strongest_symbol = max(symbols, key=lambda item: item["net_pnl"], default=None)
        top_mistake = mistakes[0] if mistakes else None
        worst_trade = top_losses[0] if top_losses else None
        best_trade = top_wins[0] if top_wins else None

        return self._natural_chat_answer(
            question=question,
            language=self._chat_language(question, language),
            summary=summary,
            review=review,
            weakest_symbol=weakest_symbol,
            weakest_session=weakest_session,
            strongest_symbol=strongest_symbol,
            top_mistake=top_mistake,
            worst_trade=worst_trade,
            best_trade=best_trade,
            rule_breaks=rule_breaks,
        )

        if language == "vi":
            lines = [
                f"Mình đang nhìn dữ liệu tháng này: {summary['trade_count']} lệnh, PnL {self._money(summary['net_pnl'])}, win rate {summary['win_rate']:.1f}%, avg R {summary['average_r']:.2f}R.",
            ]
            if any(word in q for word in ["lỗ", "lose", "loss", "thua", "sai"]):
                if weakest_symbol and weakest_symbol["net_pnl"] < 0:
                    lines.append(
                        f"Điểm kéo hiệu suất xuống rõ nhất là {weakest_symbol['name']} với {self._money(weakest_symbol['net_pnl'])}."
                    )
                if weakest_session and weakest_session["net_pnl"] < 0:
                    lines.append(
                        f"Phiên cần soi lại là {weakest_session['name']} vì đang âm {self._money(weakest_session['net_pnl'])}."
                    )
                if worst_trade:
                    lines.append(
                        f"Lệnh tệ nhất là {worst_trade['symbol']} {self._money(worst_trade['net_pnl'])}, {worst_trade['r_multiple']:.2f}R. Hãy replay lệnh này trước khi trade setup tương tự."
                    )
            elif any(word in q for word in ["cải thiện", "plan", "ngày mai", "improve", "kế hoạch"]):
                plan = review["next_session_plan"]
                lines.append(
                    f"Kế hoạch phiên tới: tối đa {plan.get('max_trades', 2)} lệnh, risk/lệnh {plan.get('risk_per_trade', '0.5%')}, focus {plan.get('focus', 'A+ setup only')}."
                )
                avoid = plan.get("avoid") or []
                if avoid:
                    lines.append(f"Tạm tránh: {', '.join(avoid)} cho đến khi có review mới.")
            else:
                lines.extend(review.get("key_findings", [])[:2])
                lines.extend(review.get("advice", [])[:2])

            if top_mistake:
                lines.append(
                    f"Lỗi lặp lại nhiều nhất trong journal là '{top_mistake['name']}' ({top_mistake['count']} lần). Trước lệnh tiếp theo hãy check riêng lỗi này."
                )
            if rule_breaks:
                lines.append(
                    f"Có {len(rule_breaks)} nhóm vi phạm rule. Đừng nới limit giữa phiên, vì đây thường là nơi mất kỷ luật."
                )
            if strongest_symbol and strongest_symbol["net_pnl"] > 0:
                lines.append(
                    f"Mặt tích cực: {strongest_symbol['name']} đang là symbol tốt nhất với {self._money(strongest_symbol['net_pnl'])}."
                )
            return "\n".join(lines[:6])

        lines = [
            f"I am reading this month's data: {summary['trade_count']} trades, PnL {self._money(summary['net_pnl'])}, win rate {summary['win_rate']:.1f}%, avg R {summary['average_r']:.2f}R.",
        ]
        if any(word in q for word in ["loss", "lose", "wrong", "mistake"]):
            if weakest_symbol and weakest_symbol["net_pnl"] < 0:
                lines.append(
                    f"The clearest drag is {weakest_symbol['name']} at {self._money(weakest_symbol['net_pnl'])}."
                )
            if weakest_session and weakest_session["net_pnl"] < 0:
                lines.append(
                    f"Review the {weakest_session['name']} session because it is down {self._money(weakest_session['net_pnl'])}."
                )
            if worst_trade:
                lines.append(
                    f"The worst trade was {worst_trade['symbol']} {self._money(worst_trade['net_pnl'])}, {worst_trade['r_multiple']:.2f}R. Replay it before taking a similar setup."
                )
        elif any(word in q for word in ["improve", "plan", "tomorrow", "next"]):
            plan = review["next_session_plan"]
            lines.append(
                f"Next session: max {plan.get('max_trades', 2)} trades, risk/trade {plan.get('risk_per_trade', '0.5%')}, focus {plan.get('focus', 'A+ setup only')}."
            )
            avoid = plan.get("avoid") or []
            if avoid:
                lines.append(f"Temporarily avoid: {', '.join(avoid)} until the next review.")
        else:
            lines.extend(review.get("key_findings", [])[:2])
            lines.extend(review.get("advice", [])[:2])

        if top_mistake:
            lines.append(
                f"Most repeated journal mistake: '{top_mistake['name']}' ({top_mistake['count']}x). Check this before the next entry."
            )
        if rule_breaks:
            lines.append(
                f"There are {len(rule_breaks)} rule-break groups. Do not loosen limits mid-session."
            )
        if strongest_symbol and strongest_symbol["net_pnl"] > 0:
            lines.append(
                f"Positive signal: {strongest_symbol['name']} is currently strongest at {self._money(strongest_symbol['net_pnl'])}."
            )
        return "\n".join(lines[:6])

    def _localized(self, language: str, en: str, vi: str) -> str:
        return vi if language == "vi" else en

    def _natural_chat_answer(
        self,
        *,
        question: str,
        language: str,
        summary: dict[str, Any],
        review: dict[str, Any],
        weakest_symbol: dict[str, Any] | None,
        weakest_session: dict[str, Any] | None,
        strongest_symbol: dict[str, Any] | None,
        top_mistake: dict[str, Any] | None,
        worst_trade: dict[str, Any] | None,
        best_trade: dict[str, Any] | None,
        rule_breaks: list[dict[str, Any]],
    ) -> str:
        q = self._ascii_lower(question)
        wants_improvement = any(
            word in q
            for word in [
                "improve",
                "better",
                "plan",
                "tomorrow",
                "next",
                "cai thien",
                "ke hoach",
                "ngay mai",
                "nen lam gi",
            ]
        )
        wants_loss_review = any(
            word in q
            for word in [
                "loss",
                "lose",
                "losing",
                "wrong",
                "mistake",
                "thua",
                " lo",
                "sai",
                "vi sao",
                "tai sao",
            ]
        )

        if language == "vi":
            return self._natural_chat_answer_vi(
                summary=summary,
                review=review,
                weakest_symbol=weakest_symbol,
                weakest_session=weakest_session,
                strongest_symbol=strongest_symbol,
                top_mistake=top_mistake,
                worst_trade=worst_trade,
                rule_breaks=rule_breaks,
                wants_improvement=wants_improvement,
                wants_loss_review=wants_loss_review,
            )

        return self._natural_chat_answer_en(
            summary=summary,
            review=review,
            weakest_symbol=weakest_symbol,
            weakest_session=weakest_session,
            strongest_symbol=strongest_symbol,
            top_mistake=top_mistake,
            worst_trade=worst_trade,
            rule_breaks=rule_breaks,
            wants_improvement=wants_improvement,
            wants_loss_review=wants_loss_review,
        )

    def _natural_chat_answer_vi(
        self,
        *,
        summary: dict[str, Any],
        review: dict[str, Any],
        weakest_symbol: dict[str, Any] | None,
        weakest_session: dict[str, Any] | None,
        strongest_symbol: dict[str, Any] | None,
        top_mistake: dict[str, Any] | None,
        worst_trade: dict[str, Any] | None,
        rule_breaks: list[dict[str, Any]],
        wants_improvement: bool,
        wants_loss_review: bool,
    ) -> str:
        parts = [self._vi_opener(summary)]
        if wants_improvement:
            plan = review["next_session_plan"]
            parts.append(
                f"Viec nen uu tien bay gio khong phai la tim them keo, ma la giam nhiet. Phien toi dat tran {plan.get('max_trades', 2)} lenh, risk moi lenh khoang {plan.get('risk_per_trade', '0.5%')}, va chi vao khi ly do entry da duoc viet ra truoc."
            )
            if weakest_symbol and weakest_symbol["net_pnl"] < 0:
                parts.append(
                    f"{weakest_symbol['name']} dang keo ket qua xuong {self._money(weakest_symbol['net_pnl'])}. Tam thoi hay coi cap nay la 'can xin phep': neu setup khong that ro, bo qua."
                )
            if weakest_session and weakest_session["net_pnl"] < 0:
                parts.append(
                    f"Phien {weakest_session['name']} cung dang khong dep. Neu thua 1 lenh trong phien nay, dung 20-30 phut thay vi vao lai ngay."
                )
        elif wants_loss_review:
            if weakest_symbol and weakest_symbol["net_pnl"] < 0:
                parts.append(
                    f"Dau vet lon nhat la {weakest_symbol['name']} voi {self._money(weakest_symbol['net_pnl'])}. Minh khong doc no la 'ban trade te', ma la co kha nang setup/thoi diem dang chua du chat luong."
                )
            if worst_trade:
                parts.append(
                    f"Lenh can replay dau tien la {worst_trade['symbol']} {self._money(worst_trade['net_pnl'])} ({worst_trade['r_multiple']:.2f}R). Xem lai 3 diem: co plan truoc khong, co duoi gia khong, va khi sai co cat dung rule khong."
                )
        else:
            parts.append(self._vi_summary_sentence(summary))

        if top_mistake:
            parts.append(
                f"Pattern dang lap lai la '{top_mistake['name']}' ({top_mistake['count']} lan). Lan toi, bien no thanh mot cau check duy nhat truoc khi bam lenh."
            )
        if rule_breaks:
            parts.append(
                f"Co {len(rule_breaks)} nhom vi pham rule, nen minh se sua ky luat truoc khi sua chien luoc."
            )
        if strongest_symbol and strongest_symbol["net_pnl"] > 0:
            parts.append(
                f"Diem sang la {strongest_symbol['name']} dang tot hon phan con lai ({self._money(strongest_symbol['net_pnl'])}). Dung voi tang size; hay dung no de tim mau setup dang hop."
            )

        parts.append(
            "Ke hoach ngan gon: trade it hon, ly do vao lenh ro hon, va dung ngay khi thay minh muon go lai."
        )
        return "\n\n".join(parts[:5])

    def _natural_chat_answer_en(
        self,
        *,
        summary: dict[str, Any],
        review: dict[str, Any],
        weakest_symbol: dict[str, Any] | None,
        weakest_session: dict[str, Any] | None,
        strongest_symbol: dict[str, Any] | None,
        top_mistake: dict[str, Any] | None,
        worst_trade: dict[str, Any] | None,
        rule_breaks: list[dict[str, Any]],
        wants_improvement: bool,
        wants_loss_review: bool,
    ) -> str:
        parts = [self._en_opener(summary)]
        if wants_improvement:
            plan = review["next_session_plan"]
            parts.append(
                f"The best improvement now is not more trades, it is less heat. Cap the next session at {plan.get('max_trades', 2)} trades, keep risk near {plan.get('risk_per_trade', '0.5%')}, and only enter when the reason is written before the trade."
            )
            if weakest_symbol and weakest_symbol["net_pnl"] < 0:
                parts.append(
                    f"{weakest_symbol['name']} is pulling results down by {self._money(weakest_symbol['net_pnl'])}. Treat it as a permission-only symbol for now: if the setup is not obvious, skip it."
                )
            if weakest_session and weakest_session["net_pnl"] < 0:
                parts.append(
                    f"The {weakest_session['name']} session also needs caution. After one loss there, step away for 20-30 minutes instead of re-entering immediately."
                )
        elif wants_loss_review:
            if weakest_symbol and weakest_symbol["net_pnl"] < 0:
                parts.append(
                    f"The clearest footprint is {weakest_symbol['name']} at {self._money(weakest_symbol['net_pnl'])}. I would read that as setup quality or timing, not as 'you cannot trade'."
                )
            if worst_trade:
                parts.append(
                    f"Replay {worst_trade['symbol']} {self._money(worst_trade['net_pnl'])} ({worst_trade['r_multiple']:.2f}R) first. Ask: did I have a plan, did I chase price, and did I exit when the idea was invalid?"
                )
        else:
            parts.append(self._en_summary_sentence(summary))

        if top_mistake:
            parts.append(
                f"One repeated pattern is '{top_mistake['name']}' ({top_mistake['count']}x). Turn that into the single pre-entry check on your next trade."
            )
        if rule_breaks:
            parts.append(
                f"There are {len(rule_breaks)} rule-break groups, so I would fix discipline before changing strategy."
            )
        if strongest_symbol and strongest_symbol["net_pnl"] > 0:
            parts.append(
                f"The useful bright spot is {strongest_symbol['name']} at {self._money(strongest_symbol['net_pnl'])}. Do not size up yet; use it as a clue for what kind of setup is working."
            )

        parts.append(
            "Short plan: trade less, require a written reason, and stop as soon as you feel yourself trying to win it back."
        )
        return "\n\n".join(parts[:5])

    def _chat_language(self, question: str, language: str) -> str:
        if language == "vi":
            return "vi"
        lowered = self._ascii_lower(question)
        vietnamese_markers = [
            "toi",
            "minh",
            "ban",
            "cai thien",
            "thua",
            " lo",
            "lenh",
            "phien",
            "ke hoach",
            "ngay mai",
            "tai sao",
            "vi sao",
            "nen",
        ]
        return "vi" if any(marker in lowered for marker in vietnamese_markers) else "en"

    def _ascii_lower(self, value: str) -> str:
        replacements = {
            "à": "a", "á": "a", "ạ": "a", "ả": "a", "ã": "a",
            "â": "a", "ầ": "a", "ấ": "a", "ậ": "a", "ẩ": "a", "ẫ": "a",
            "ă": "a", "ằ": "a", "ắ": "a", "ặ": "a", "ẳ": "a", "ẵ": "a",
            "è": "e", "é": "e", "ẹ": "e", "ẻ": "e", "ẽ": "e",
            "ê": "e", "ề": "e", "ế": "e", "ệ": "e", "ể": "e", "ễ": "e",
            "ì": "i", "í": "i", "ị": "i", "ỉ": "i", "ĩ": "i",
            "ò": "o", "ó": "o", "ọ": "o", "ỏ": "o", "õ": "o",
            "ô": "o", "ồ": "o", "ố": "o", "ộ": "o", "ổ": "o", "ỗ": "o",
            "ơ": "o", "ờ": "o", "ớ": "o", "ợ": "o", "ở": "o", "ỡ": "o",
            "ù": "u", "ú": "u", "ụ": "u", "ủ": "u", "ũ": "u",
            "ư": "u", "ừ": "u", "ứ": "u", "ự": "u", "ử": "u", "ữ": "u",
            "ỳ": "y", "ý": "y", "ỵ": "y", "ỷ": "y", "ỹ": "y",
            "đ": "d",
        }
        return "".join(replacements.get(char, char) for char in value.lower())

    def _vi_opener(self, summary: dict[str, Any]) -> str:
        trade_count = summary["trade_count"]
        net_pnl = summary["net_pnl"]
        win_rate = summary["win_rate"]
        avg_r = summary["average_r"]
        if trade_count == 0:
            return "Hien tai minh chua thay du lenh da dong de ket luan chac. Minh se coach theo huong an toan truoc."
        if net_pnl < 0:
            return f"Minh thay thang nay dang am {self._money(net_pnl)} sau {trade_count} lenh, win rate {win_rate:.1f}% va avg R {avg_r:.2f}R. Chua can hoang; mau du lieu con nho, nhung co vai diem nen sua ngay."
        return f"Thang nay dang duong {self._money(net_pnl)} sau {trade_count} lenh. Minh se tap trung giup ban giu edge thay vi trade hung phan."

    def _en_opener(self, summary: dict[str, Any]) -> str:
        trade_count = summary["trade_count"]
        net_pnl = summary["net_pnl"]
        win_rate = summary["win_rate"]
        avg_r = summary["average_r"]
        if trade_count == 0:
            return "I do not have enough closed trades to make a strong read yet, so I would coach defensively first."
        if net_pnl < 0:
            return f"You are down {self._money(net_pnl)} this month across {trade_count} trades, with {win_rate:.1f}% win rate and {avg_r:.2f}R avg R. No need to panic; the sample is small, but there are a few things to tighten now."
        return f"You are up {self._money(net_pnl)} this month across {trade_count} trades. I would focus on protecting the edge, not pressing harder."

    def _vi_summary_sentence(self, summary: dict[str, Any]) -> str:
        return f"Buc tranh chinh: {summary['trade_count']} lenh, PnL {self._money(summary['net_pnl'])}, profit factor {summary['profit_factor']:.2f}. Neu chi sua mot thu, hay sua chat luong entry truoc."

    def _en_summary_sentence(self, summary: dict[str, Any]) -> str:
        return f"The main picture: {summary['trade_count']} trades, PnL {self._money(summary['net_pnl'])}, profit factor {summary['profit_factor']:.2f}. If you improve one thing first, improve entry quality."

    def _coach_review_with_ai(
        self,
        context: dict[str, Any],
        language: str,
    ) -> dict[str, Any]:
        normalized_language = "vi" if language == "vi" else "en"
        local_review = {
            **self._coach_review(context),
            "source": "local",
            "language": normalized_language,
        }
        ai_review = AiProviderService().coach_review(
            context,
            local_review,
            normalized_language,
        )
        return ai_review or local_review

    def _coach_review(self, context: dict[str, Any]) -> dict[str, Any]:
        summary = context["summary"]
        rule_breaks = context.get("rule_breaks", [])
        mistakes = context.get("mistakes", [])
        symbols = context.get("symbols", [])
        sessions = context.get("sessions", [])
        top_losses = context.get("top_losses", [])
        top_wins = context.get("top_wins", [])
        net_pnl = summary["net_pnl"]
        trade_count = summary["trade_count"]
        win_rate = summary["win_rate"]
        avg_r = summary["average_r"] or 0
        profit_factor = summary["profit_factor"]

        if trade_count == 0:
            return {
                "headline": "No closed trades in this period",
                "risk_level": "neutral",
                "key_findings": ["No normalized closed trades are available yet."],
                "advice": [
                    "Sync MT5 after trades close.",
                    "Write a pre-market plan before taking the next setup.",
                ],
                "next_session_plan": {
                    "focus": "Wait for A+ setups only",
                    "max_trades": 2,
                    "risk_per_trade": "0.25% - 0.5%",
                },
            }

        worst_symbol = min(symbols, key=lambda item: item["net_pnl"], default=None)
        best_symbol = max(symbols, key=lambda item: item["net_pnl"], default=None)
        worst_session = min(sessions, key=lambda item: item["net_pnl"], default=None)
        top_mistake = mistakes[0] if mistakes else None
        critical_breaks = [
            item for item in rule_breaks if item.get("severity") == "critical"
        ]

        key_findings: list[str] = []
        advice: list[str] = []

        key_findings.append(
            f"Closed {trade_count} trades with net PnL {self._money(net_pnl)} and win rate {win_rate:.1f}%."
        )
        key_findings.append(
            f"Average R is {avg_r:.2f}R and profit factor is {profit_factor:.2f}."
        )

        if worst_symbol and worst_symbol["net_pnl"] < 0:
            key_findings.append(
                f"{worst_symbol['name']} is the weakest symbol in this period at {self._money(worst_symbol['net_pnl'])}."
            )
            advice.append(
                f"Reduce or pause {worst_symbol['name']} until the next review unless a written A+ setup appears."
            )
        if best_symbol and best_symbol["net_pnl"] > 0:
            key_findings.append(
                f"{best_symbol['name']} is the strongest symbol at {self._money(best_symbol['net_pnl'])}."
            )
        if worst_session and worst_session["net_pnl"] < 0:
            advice.append(
                f"Review {worst_session['name']} session entries; this session contributed {self._money(worst_session['net_pnl'])}."
            )
        if top_mistake:
            key_findings.append(
                f"Most repeated journal mistake: {top_mistake['name']} ({top_mistake['count']}x)."
            )
            advice.append(
                f"Before the next trade, explicitly check: am I repeating '{top_mistake['name']}'?"
            )
        if rule_breaks:
            key_findings.append(
                f"{len(rule_breaks)} rule break types were detected in this period."
            )
            advice.append("Keep trade blocking enabled and do not loosen core limits mid-session.")
        if top_losses:
            loss = top_losses[0]
            advice.append(
                f"Replay the worst trade ({loss['symbol']} {self._money(loss['net_pnl'])}) before taking another similar setup."
            )
        if net_pnl < 0 and win_rate < 45:
            advice.append("Limit the next session to 1-2 trades and cut size until win rate stabilizes.")
        elif net_pnl > 0 and profit_factor >= 1.8:
            advice.append("Keep the same risk profile; do not scale up until this edge repeats across another period.")
        else:
            advice.append("Trade only setups already written in the plan; skip impulse entries.")

        risk_level = "low"
        if net_pnl < 0 or critical_breaks or avg_r < 0:
            risk_level = "high" if critical_breaks or win_rate < 25 else "medium"

        return {
            "headline": self._headline(net_pnl, win_rate, rule_breaks),
            "risk_level": risk_level,
            "key_findings": key_findings[:5],
            "advice": advice[:5],
            "next_session_plan": {
                "max_trades": 2 if risk_level != "low" else 3,
                "risk_per_trade": "0.25%" if risk_level == "high" else "0.5%",
                "focus": best_symbol["name"] if best_symbol else "A+ setup only",
                "avoid": [worst_symbol["name"]] if worst_symbol and worst_symbol["net_pnl"] < 0 else [],
            },
        }

    def _headline(
        self,
        net_pnl: float,
        win_rate: float,
        rule_breaks: list[dict[str, Any]],
    ) -> str:
        if rule_breaks:
            return "Discipline is the main issue this period"
        if net_pnl < 0 and win_rate < 45:
            return "Losses are driven by low win rate and negative expectancy"
        if net_pnl < 0:
            return "Period is negative; review sizing and weakest symbol"
        if net_pnl > 0:
            return "Period is profitable; protect the edge and avoid overtrading"
        return "Flat period; wait for cleaner setups"

    def _closed_trades(
        self,
        account_id: int | None,
        start: date,
        end: date,
    ) -> list[NormalizedTrade]:
        query = self._db.query(NormalizedTrade).filter(
            NormalizedTrade.status.in_(["closed", "breakeven"]),
            NormalizedTrade.closed_at >= datetime.combine(start, datetime.min.time()),
            NormalizedTrade.closed_at <= datetime.combine(end, datetime.max.time()),
        )
        if account_id is not None:
            query = query.filter(NormalizedTrade.account_id == account_id)
        return query.order_by(NormalizedTrade.closed_at.asc(), NormalizedTrade.id.asc()).all()

    def _summary(self, trades: list[NormalizedTrade]) -> dict[str, Any]:
        wins = [trade for trade in trades if trade.net_pnl > 0]
        losses = [trade for trade in trades if trade.net_pnl < 0]
        gross_profit = sum(trade.net_pnl for trade in wins)
        gross_loss = abs(sum(trade.net_pnl for trade in losses))
        r_values = [trade.r_multiple for trade in trades if trade.r_multiple is not None]
        return {
            "trade_count": len(trades),
            "win_count": len(wins),
            "loss_count": len(losses),
            "win_rate": round(len(wins) / len(trades) * 100, 2) if trades else 0,
            "net_pnl": round(sum(trade.net_pnl for trade in trades), 2),
            "gross_profit": round(gross_profit, 2),
            "gross_loss": round(gross_loss, 2),
            "profit_factor": round(gross_profit / gross_loss, 4) if gross_loss else round(gross_profit, 4),
            "average_r": round(sum(r_values) / len(r_values), 4) if r_values else 0,
            "best_r": round(max(r_values), 4) if r_values else 0,
            "worst_r": round(min(r_values), 4) if r_values else 0,
        }

    def _group_payload(self, trades: list[NormalizedTrade], key_fn) -> list[dict[str, Any]]:
        grouped: dict[str, list[NormalizedTrade]] = defaultdict(list)
        for trade in trades:
            grouped[key_fn(trade)].append(trade)
        payload = []
        for name, items in grouped.items():
            summary = self._summary(items)
            payload.append({"name": name, **summary})
        return sorted(payload, key=lambda item: item["net_pnl"])

    def _mistake_payload(self, trades: list[NormalizedTrade]) -> list[dict[str, Any]]:
        counter: Counter[str] = Counter()
        for trade in trades:
            if trade.journal and trade.journal.mistakes:
                counter.update(str(item) for item in trade.journal.mistakes if str(item).strip())
        return [
            {"name": name, "count": count}
            for name, count in counter.most_common(8)
        ]

    def _rule_breaks(
        self,
        account_id: int | None,
        start: date,
        end: date,
    ) -> list[RuleBreak]:
        query = self._db.query(RuleBreak).filter(
            RuleBreak.detected_at >= datetime.combine(start, datetime.min.time()),
            RuleBreak.detected_at <= datetime.combine(end, datetime.max.time()),
        )
        if account_id is not None:
            query = query.filter(RuleBreak.account_id == account_id)
        return query.order_by(RuleBreak.detected_at.desc()).all()

    def _rule_break_payload(self, rule_breaks) -> list[dict[str, Any]]:
        grouped: dict[str, list[RuleBreak]] = defaultdict(list)
        for item in rule_breaks or []:
            grouped[item.rule_code].append(item)
        payload = []
        for code, items in grouped.items():
            severity = "critical" if any(item.severity == "critical" for item in items) else items[0].severity
            payload.append(
                {
                    "rule_code": code,
                    "severity": severity,
                    "count": len(items),
                    "message": items[0].message,
                }
            )
        return sorted(payload, key=lambda item: item["count"], reverse=True)

    def _events(self, start: date, end: date) -> list[EconomicEvent]:
        return (
            self._db.query(EconomicEvent)
            .filter(
                EconomicEvent.event_time >= datetime.combine(start, datetime.min.time()),
                EconomicEvent.event_time <= datetime.combine(end, datetime.max.time()),
                EconomicEvent.impact.in_(["high", "medium"]),
            )
            .order_by(EconomicEvent.event_time.asc())
            .limit(20)
            .all()
        )

    def _recent_notes(self, account_id: int | None) -> list[NotebookNote]:
        query = self._db.query(NotebookNote)
        if account_id is not None:
            query = query.filter(NotebookNote.account_id == account_id)
        return query.order_by(NotebookNote.updated_at.desc()).limit(5).all()

    def _guardrail_payload(
        self,
        account_id: int | None,
        target_date: date,
    ) -> dict[str, Any]:
        if account_id is None:
            return {}
        return GuardrailService(self._db).status(account_id, target_date)

    def _trade_payload(self, trade: NormalizedTrade) -> dict[str, Any]:
        return {
            "id": trade.id,
            "symbol": trade.symbol,
            "direction": trade.direction,
            "volume": trade.volume,
            "net_pnl": round(trade.net_pnl, 2),
            "r_multiple": round(trade.r_multiple or 0, 4),
            "opened_at": trade.opened_at.isoformat() if trade.opened_at else None,
            "closed_at": trade.closed_at.isoformat() if trade.closed_at else None,
            "setup": trade.journal.setup if trade.journal and trade.journal.setup else trade.setup_tag,
            "session": trade.session,
        }

    def _event_payload(self, event: EconomicEvent) -> dict[str, Any]:
        return {
            "event_time": event.event_time.isoformat(),
            "currency": event.currency,
            "impact": event.impact,
            "title": event.title,
        }

    def _note_payload(self, note: NotebookNote) -> dict[str, Any]:
        return {
            "title": note.title,
            "template": note.template,
            "plan": (note.plan or "")[:240],
            "note": (note.note or "")[:240],
        }

    def _top_losses(self, trades: list[NormalizedTrade]) -> list[NormalizedTrade]:
        return sorted([trade for trade in trades if trade.net_pnl < 0], key=lambda trade: trade.net_pnl)[:5]

    def _top_wins(self, trades: list[NormalizedTrade]) -> list[NormalizedTrade]:
        return sorted([trade for trade in trades if trade.net_pnl > 0], key=lambda trade: trade.net_pnl, reverse=True)[:5]

    def _period_bounds(self, period: str, target: date) -> tuple[date, date]:
        normalized = period.lower()
        if normalized == "week":
            start = target - timedelta(days=target.weekday())
            return start, start + timedelta(days=6)
        if normalized == "month":
            return target.replace(day=1), target
        return target, target

    def _today(self) -> date:
        return (datetime.utcnow() + timedelta(hours=7)).date()

    def _money(self, value: float) -> str:
        sign = "+" if value > 0 else "-" if value < 0 else ""
        return f"{sign}${abs(value):.0f}"
