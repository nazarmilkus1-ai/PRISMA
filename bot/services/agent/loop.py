"""Background worker: a work cycle every few minutes and a report every hour, each claimed atomically in the database."""
from __future__ import annotations

import asyncio
import logging

from db import rpc

from . import brain, config, memory, report

logger = logging.getLogger(__name__)


async def run_worker(bot, stop: asyncio.Event) -> None:
    if not config.ENABLED:
        logger.info("autonomous agent disabled (AGENT_ENABLED=0)")
        return
    await asyncio.sleep(45)
    while not stop.is_set():
        try:
            if (await rpc.bot_agent_claim("cycle", config.CYCLE_SECONDS)).data is True:
                result = await brain.run_cycle(bot)
                logger.info("agent cycle: %s", result.get("summary"))
            if (await rpc.bot_agent_claim("report", config.REPORT_SECONDS)).data is True:
                await report.send_hourly(bot)
            if (await rpc.bot_agent_claim("consolidate", 86_400)).data is True:
                await memory.consolidate()
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("agent worker iteration failed")
        try:
            await asyncio.wait_for(stop.wait(), timeout=60)
        except asyncio.TimeoutError:
            pass
