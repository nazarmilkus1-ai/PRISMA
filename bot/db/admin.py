from db.rpc import bot_list_appeals, bot_manage_appeal, bot_list_pending_applications, bot_list_open_reports, bot_search_players

async def pending_applications(admin_tg_id: int, limit: int = 10):
    result = await bot_list_pending_applications(admin_tg_id, limit)
    if result.error:
        return None, result.error
    return result.data if isinstance(result.data, list) else [], None

async def open_reports(admin_tg_id: int, limit: int = 15):
    result = await bot_list_open_reports(admin_tg_id, limit)
    if result.error:
        return None, result.error
    return result.data if isinstance(result.data, list) else [], None

async def open_appeals(admin_tg_id: int, limit: int = 15):
    result = await bot_list_appeals(admin_tg_id, status="ALL", limit=limit * 2)
    if result.error:
        return None, result.error
    rows = result.data if isinstance(result.data, list) else []
    active = [row for row in rows if str(row.get("status") or "").upper() in {"OPEN", "IN_REVIEW"}]
    return active[:limit], None


async def find_players(admin_tg_id: int, query: str, limit: int = 10):
    result = await bot_search_players(admin_tg_id, query, limit)
    if result.error:
        return None, result.error
    return result.data if isinstance(result.data, list) else [], None

