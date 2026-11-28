"""Background worker: a work cycle every few minutes and a report every hour, each claimed atomically in the database."""
from __future__ import annotations

import asyncio
import logging

from db import rpc

from . import autopilot, brain, config, memory, report

logger = logging.getLogger(__name__)


async def _cycle_seconds() -> int:
    """Back-to-back cycles while the agent has work (autonomous mode: always), the slow timer otherwise or on pause."""
    if not config.CODE_ACCESS:
        return config.ASSISTANT_CYCLE_SECONDS  # a question from an admin wakes the worker earlier (jobs.wake)
    try:
        state = (await rpc.bot_agent_state_get()).data or {}
        goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
        return autopilot.cycle_seconds(state, goals)
    except Exception:
        return config.CYCLE_SECONDS


MAINTAIN_SECONDS = 100  # merging and un-sticking PRs do not wait for the end of a long work cycle


async def _maintain_loop(bot, stop: asyncio.Event) -> None:
    await asyncio.sleep(30)
    while not stop.is_set():
        try:
            state = (await rpc.bot_agent_state_get()).data or {}
            if not state.get("paused") and (await rpc.bot_agent_claim("maintain", MAINTAIN_SECONDS)).data is True:
                await brain.maintain(bot)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("agent maintenance iteration failed")
        try:
            await asyncio.wait_for(stop.wait(), timeout=30)
        except asyncio.TimeoutError:
            pass


async def run_worker(bot, stop: asyncio.Event) -> None:
    if not config.ENABLED:
        logger.info("autonomous agent disabled (AGENT_ENABLED=0)")
        return
    maintainer = asyncio.create_task(_maintain_loop(bot, stop))
    try:
        await _work_loop(bot, stop)
    finally:
        maintainer.cancel()


async def _work_loop(bot, stop: asyncio.Event) -> None:
    await asyncio.sleep(45)
    while not stop.is_set():
        try:
            if (await rpc.bot_agent_claim("cycle", await _cycle_seconds())).data is True:
                result = await brain.run_cycle(bot)
                logger.info("agent cycle: %s", result.get("summary"))
            if config.CODE_ACCESS and (await rpc.bot_agent_claim("report", config.REPORT_SECONDS)).data is True:
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
