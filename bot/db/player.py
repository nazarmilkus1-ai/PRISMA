from db.rpc import (
    bot_get_achievements,
    bot_get_battles,
    bot_list_events,
    bot_create_appeal,
    bot_get_leaderboard,
    bot_get_notification_preferences,
    bot_get_own_punishments,
    bot_get_player_appeals,
    bot_get_player_reports,
    bot_get_player_activity_stats,
    bot_get_profile,
    bot_get_server_metrics,
    bot_get_online_players,
    bot_register_event,
    bot_set_notification_preference,
    bot_start_battle,
    bot_unregister_event,
)

async def _user(tg_id: int):
    result = await bot_get_profile(tg_id)
    if result.error:
        return None, result.error
    if not isinstance(result.data, dict):
        return None, "INVALID_RPC_RESPONSE"
    if result.data.get("error"):
        return None, str(result.data["error"])
    return result.data, None


async def get_center(tg_id: int):
    user, err = await _user(tg_id)
    if err or not user:
        return None, err or "USER_NOT_FOUND"

    stats, stats_err = await get_stats(tg_id)
    achievements, achievements_err = await get_achievements(tg_id)
    punishments, punishments_err = await get_own_punishments(tg_id)
    prefs, prefs_err = await get_notification_preferences(tg_id)

    errors = [stats_err, achievements_err, punishments_err, prefs_err]
    first_error = next((item for item in errors if item), None)
    if first_error:
        return None, first_error

    return {
        "user": user,
        "stats": stats,
        "achievements": achievements,
        "punishments": punishments,
        "preferences": prefs,
    }, None


async def get_stats(tg_id: int):
    result = await bot_get_player_activity_stats(tg_id)
    if result.error:
        return {}, result.error
    if not isinstance(result.data, dict):
        return {}, "INVALID_RPC_RESPONSE"
    if result.data.get("error"):
        return {}, str(result.data["error"])
    return result.data, None


async def get_achievements(tg_id: int):
    result = await bot_get_achievements(tg_id)
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None


async def get_own_punishments(tg_id: int):
    result = await bot_get_own_punishments(tg_id)
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None


async def get_player_reports(tg_id: int):
    result = await bot_get_player_reports(tg_id)
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None


async def get_notification_preferences(tg_id: int):
    result = await bot_get_notification_preferences(tg_id)
    if result.error:
        return {}, result.error
    if not isinstance(result.data, dict):
        return {}, "INVALID_RPC_RESPONSE"
    return result.data, None


async def set_notification_preference(tg_id: int, key: str, enabled: bool):
    allowed = {
        "news",
        "events",
        "server_status",
        "clan_news",
        "social",
        "battles",
        "market",
        "moderation",
        "polls",
    }
    if key not in allowed:
        return False, "INVALID_KEY"

    result = await bot_set_notification_preference(tg_id, key, enabled)
    if result.error:
        return False, result.error
    if not isinstance(result.data, dict):
        return False, "INVALID_RPC_RESPONSE"
    if result.data.get("error"):
        return False, str(result.data["error"])
    return True, result.data


async def list_events(tg_id: int, limit: int = 20):
    result = await bot_list_events(tg_id, limit)
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None


async def register_event(tg_id: int, event_id: str):
    result = await bot_register_event(tg_id, event_id)
    if result.error:
        return False, result.error
    data = result.data
    if not isinstance(data, dict):
        return False, "INVALID_RPC_RESPONSE"
    if data.get("error"):
        return False, str(data["error"])
    return bool(data.get("success")), data


async def unregister_event(tg_id: int, event_id: str):
    result = await bot_unregister_event(tg_id, event_id)
    if result.error:
        return False, result.error
    data = result.data
    if not isinstance(data, dict):
        return False, "INVALID_RPC_RESPONSE"
    if data.get("error"):
        return False, str(data["error"])
    return bool(data.get("success")), data


async def start_battle(tg_id: int, opponent_nickname: str):
    result = await bot_start_battle(tg_id, opponent_nickname.strip())
    if result.error:
        return None, result.error
    data = result.data
    if not isinstance(data, dict):
        return None, "INVALID_RPC_RESPONSE"
    if data.get("error"):
        return None, str(data["error"])
    if not data.get("success"):
        return None, "BATTLE_CREATE_FAILED"
    return data, None


async def list_battles(tg_id: int, limit: int = 10):
    result = await bot_get_battles(tg_id, limit)
    if result.error:
        return [], result.error
    data = result.data
    if isinstance(data, dict) and data.get("error"):
        return [], str(data["error"])
    if not isinstance(data, list):
        return [], "INVALID_RPC_RESPONSE"
    return data, None


async def get_player_appeals(tg_id: int):
    result = await bot_get_player_appeals(tg_id)
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None


async def create_appeal(tg_id: int, reason: str, punishment_id: str | None = None):
    result = await bot_create_appeal(tg_id, reason.strip(), punishment_id)
    if result.error:
        return None, result.error
    if not isinstance(result.data, dict):
        return None, "INVALID_RPC_RESPONSE"
    if result.data.get("error"):
        return None, str(result.data["error"])
    if not result.data.get("success"):
        return None, "APPEAL_CREATE_FAILED"
    return result.data, None


async def get_server_metrics():
    result = await bot_get_server_metrics()
    if result.error:
        return {}, result.error
    if not isinstance(result.data, dict):
        return {}, "INVALID_RPC_RESPONSE"
    return result.data, None


async def get_online_players():
    result = await bot_get_online_players()
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None


async def leaderboard(field: str, limit: int = 10):
    if field not in {"rating", "activity_score", "xp", "level"}:
        return [], "INVALID_FIELD"
    result = await bot_get_leaderboard(field, limit)
    if result.error:
        return [], result.error
    if not isinstance(result.data, list):
        return [], "INVALID_RPC_RESPONSE"
    return result.data, None
