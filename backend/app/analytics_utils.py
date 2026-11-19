from datetime import datetime, timezone, timedelta
from typing import List, Tuple, Optional
import zoneinfo

def merge_intervals(intervals: List[Tuple[datetime, datetime]]) -> List[Tuple[datetime, datetime]]:
    """Merges overlapping or touching time intervals."""
    if not intervals:
        return []
    intervals.sort(key=lambda x: x[0])
    merged = [intervals[0]]
    for current in intervals[1:]:
        last = merged[-1]
        if current[0] <= last[1]:
            merged[-1] = (last[0], max(last[1], current[1]))
        else:
            merged.append(current)
    return merged

def calculate_unique_task_seconds(
    tasks: List,
    session_start: datetime,
    session_end: datetime,
    breaks: List
) -> float:
    """Calculates unique task active seconds within a session, excluding breaks."""
    task_intervals = []
    for task in tasks:
        task_start = task.started_at
        if task_start is None:
            continue
        task_end = task.ended_at or datetime.now(timezone.utc)
        overlap_start = max(task_start, session_start)
        overlap_end = min(task_end, session_end)
        if overlap_start < overlap_end:
            task_intervals.append((overlap_start, overlap_end))

    merged_task_intervals = merge_intervals(task_intervals)
    total_task_seconds = sum((i[1] - i[0]).total_seconds() for i in merged_task_intervals)
    break_seconds_in_task_time = 0

    break_intervals = []
    for break_record in breaks:
        break_start = break_record.started_at
        break_end = break_record.ended_at or datetime.now(timezone.utc)
        overlap_start = max(break_start, session_start)
        overlap_end = min(break_end, session_end)
        if overlap_start < overlap_end:
            break_intervals.append((overlap_start, overlap_end))

    merged_break_intervals = merge_intervals(break_intervals)
    for task_int in merged_task_intervals:
        for break_int in merged_break_intervals:
            overlap_start = max(task_int[0], break_int[0])
            overlap_end = min(task_int[1], break_int[1])
            if overlap_start < overlap_end:
                break_seconds_in_task_time += (overlap_end - overlap_start).total_seconds()

    return max(0, total_task_seconds - break_seconds_in_task_time)

def get_week_start_end():
    """Get the start and end of the past 7 days in UTC"""
    end_of_day = datetime.now(timezone.utc).replace(hour=23, minute=59, second=59, microsecond=999999)
    start_of_day = end_of_day - timedelta(days=6)
    start_of_day = start_of_day.replace(hour=0, minute=0, second=0, microsecond=0)
    return start_of_day, end_of_day

def get_start_end_for_period(period: Optional[str], user_timezone: str = "UTC"):
    """
    Get start and end datetime for a period in the user's timezone, then convert to UTC.
    Supports: today, yesterday, this_week, last_week, this_month, last_month
    """
    try:
        tz = zoneinfo.ZoneInfo(user_timezone)
    except Exception:
        tz = timezone.utc

    now = datetime.now(tz)
    p = (period or "this_week").lower()

    if p == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        end = now.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif p == "yesterday":
        yesterday = now - timedelta(days=1)
        start = yesterday.replace(hour=0, minute=0, second=0, microsecond=0)
        end = yesterday.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif p == "this_week":
        monday = now - timedelta(days=now.weekday())
        start = monday.replace(hour=0, minute=0, second=0, microsecond=0)
        sunday = start + timedelta(days=6, hours=23, minutes=59, seconds=59, microseconds=999999)
        end = sunday
    elif p == "last_week":
        monday = now - timedelta(days=now.weekday() + 7)
        start = monday.replace(hour=0, minute=0, second=0, microsecond=0)
        sunday = start + timedelta(days=6, hours=23, minutes=59, seconds=59, microseconds=999999)
        end = sunday
    elif p == "this_month":
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        next_month = (start + timedelta(days=32)).replace(day=1)
        end = next_month - timedelta(microseconds=1)
    elif p == "last_month":
        first_this_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        last_last_month = first_this_month - timedelta(microseconds=1)
        start = last_last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end = last_last_month.replace(hour=23, minute=59, second=59, microsecond=999999)
    else:
        monday = now - timedelta(days=now.weekday())
        start = monday.replace(hour=0, minute=0, second=0, microsecond=0)
        sunday = start + timedelta(days=6, hours=23, minutes=59, seconds=59, microseconds=999999)
        end = sunday

    start_utc = start.astimezone(timezone.utc)
    end_utc = end.astimezone(timezone.utc)
    return start_utc, end_utc

def get_previous_start_end_for_period(period: Optional[str], user_timezone: str = "UTC"):
    """Get start and end for the previous equivalent period."""
    try:
        tz = zoneinfo.ZoneInfo(user_timezone)
    except Exception:
        tz = timezone.utc

    now = datetime.now(tz)
    p = (period or "this_week").lower()

    if p == "today":
        yesterday = now - timedelta(days=1)
        start = yesterday.replace(hour=0, minute=0, second=0, microsecond=0)
        end = yesterday.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif p == "yesterday":
        day_before = now - timedelta(days=2)
        start = day_before.replace(hour=0, minute=0, second=0, microsecond=0)
        end = day_before.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif p == "this_week":
        monday = now - timedelta(days=now.weekday() + 7)
        start = monday.replace(hour=0, minute=0, second=0, microsecond=0)
        sunday = start + timedelta(days=6, hours=23, minutes=59, seconds=59, microseconds=999999)
        end = sunday
    elif p == "last_week":
        monday = now - timedelta(days=now.weekday() + 14)
        start = monday.replace(hour=0, minute=0, second=0, microsecond=0)
        sunday = start + timedelta(days=6, hours=23, minutes=59, seconds=59, microseconds=999999)
        end = sunday
    elif p == "this_month":
        first_this_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        last_last_month = first_this_month - timedelta(microseconds=1)
        start = last_last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end = last_last_month.replace(hour=23, minute=59, second=59, microsecond=999999)
    elif p == "last_month":
        first_this_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        last_last_month = first_this_month - timedelta(microseconds=1)
        prev_last_month = last_last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0) - timedelta(microseconds=1)
        start = prev_last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end = prev_last_month.replace(hour=23, minute=59, second=59, microsecond=999999)
    else:
        monday = now - timedelta(days=now.weekday() + 7)
        start = monday.replace(hour=0, minute=0, second=0, microsecond=0)
        sunday = start + timedelta(days=6, hours=23, minutes=59, seconds=59, microseconds=999999)
        end = sunday

    start_utc = start.astimezone(timezone.utc)
    end_utc = end.astimezone(timezone.utc)
    return start_utc, end_utc

def parse_date_range(
    start_date: Optional[str],
    end_date: Optional[str],
    period: Optional[str],
    user_timezone: str = "UTC"
) -> Tuple[datetime, datetime]:
    """
    Parse date range from explicit dates, period, or default to this_week.
    Returns (start_utc, end_utc) in UTC.
    """
    try:
        tz = zoneinfo.ZoneInfo(user_timezone)
    except Exception:
        tz = timezone.utc

    if start_date and end_date:
        try:
            start = datetime.strptime(start_date, "%Y-%m-%d").replace(tzinfo=tz)
            end = datetime.strptime(end_date, "%Y-%m-%d").replace(hour=23, minute=59, second=59, microsecond=999999, tzinfo=tz)
            return start.astimezone(timezone.utc), end.astimezone(timezone.utc)
        except ValueError:
            pass

    if period:
        return get_start_end_for_period(period, user_timezone)

    return get_start_end_for_period("this_week", user_timezone)

def ensure_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Ensures a datetime is timezone-aware in UTC, handling offset-naive datetimes."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt

