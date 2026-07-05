from datetime import date, datetime, time


def utc_now() -> datetime:
    return datetime.utcnow()


def day_bounds(value: date) -> tuple[datetime, datetime]:
    return datetime.combine(value, time.min), datetime.combine(value, time.max)
