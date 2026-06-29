"""Background scheduler for daily Tesla usage snapshots."""

import asyncio
import logging

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

from app.config import settings
from app.daily_agent import run_daily_agent
from app.database import SessionLocal

logger = logging.getLogger(__name__)
scheduler = BackgroundScheduler()


def _run_daily_job():
    db = SessionLocal()
    try:
        asyncio.run(run_daily_agent(db))
    except Exception:
        logger.exception("Daily agent job failed")
    finally:
        db.close()


def start_scheduler():
    if scheduler.running:
        return
    scheduler.add_job(
        _run_daily_job,
        CronTrigger(
            hour=settings.daily_snapshot_hour,
            minute=settings.daily_snapshot_minute,
        ),
        id="daily_tesla_snapshot",
        replace_existing=True,
    )
    scheduler.start()
    logger.info(
        "Daily agent scheduled at %02d:%02d",
        settings.daily_snapshot_hour,
        settings.daily_snapshot_minute,
    )
