import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Any
from config import supabase

logger = logging.getLogger(__name__)
_executor = ThreadPoolExecutor(max_workers=10, thread_name_prefix="prisma-rpc")

@dataclass
class RPCResult:
    data: Any = None
    error: str | None = None

async def bot_get_public_module_states():
    return await call_rpc_async("get_public_module_states", {})


TRANSIENT_RPC_ERROR_MARKERS = (
    "server disconnected",
    "remoteprotocolerror",
    "connection reset",
    "connection aborted",
    "connection refused",
    "connection closed",
    "broken pipe",
    "network is unreachable",
    "temporarily unavailable",
    "timed out",
    "timeout",
    "eof",
    "502 bad gateway",
    "503 service unavailable",
    "504 gateway timeout",
)

TRANSIENT_OS_ERRNOS = {54, 104, 110, 111, 113, 10054, 10060, 10061}


def _is_transient_rpc_error(exc: Exception) -> bool:
    if isinstance(exc, (asyncio.TimeoutError, ConnectionError, BrokenPipeError)):
        return True

    if isinstance(exc, OSError) and getattr(exc, "errno", None) in TRANSIENT_OS_ERRNOS:
        return True

    exc_text = f"{type(exc).__module__}.{type(exc).__name__}: {exc}".casefold()
    return any(marker in exc_text for marker in TRANSIENT_RPC_ERROR_MARKERS)


async def call_rpc_async(
    func_name: str,
    params: dict,
    *,
    retries: int = 0,
    retry_delay_seconds: float = 0.5,
) -> RPCResult:
    loop = asyncio.get_running_loop()

    def execute():
        return supabase.rpc(func_name, params).execute()

    for attempt in range(retries + 1):
        try:
            response = await loop.run_in_executor(_executor, execute)
            return RPCResult(data=response.data)
        except Exception as exc:
            is_last_attempt = attempt >= retries
            if not is_last_attempt and _is_transient_rpc_error(exc):
                delay = retry_delay_seconds * (2**attempt)
                logger.warning(
                    "Transient RPC %s failure (%d/%d): %s; retrying in %.1fs",
                    func_name,
                    attempt + 1,
                    retries + 1,
                    exc,
                    delay,
                )
                await asyncio.sleep(delay)
                continue

            logger.error(
                "RPC %s failed after %d attempt(s): %s",
                func_name,
                attempt + 1,
                exc,
            )
            return RPCResult(error=str(exc))

    return RPCResult(error=f"RPC {func_name} failed without a result")



async def bot_touch_user(tg_id, username=None, first_name=None, last_name=None, full_name=None, context="GROUP"):
    return await call_rpc_async("bot_touch_user", {
        "p_tg_id": tg_id,
        "p_username": username,
        "p_first_name": first_name,
        "p_last_name": last_name,
        "p_full_name": full_name,
        "p_context": context,
    })

async def bot_set_community_membership(
    tg_id,
    username=None,
    first_name=None,
    last_name=None,
    full_name=None,
    is_member=True,
):
    return await call_rpc_async("bot_set_community_membership", {
        "p_tg_id": tg_id,
        "p_username": username,
        "p_first_name": first_name,
        "p_last_name": last_name,
        "p_full_name": full_name,
        "p_is_member": is_member,
    })

async def bot_list_community_membership_candidates():
    return await call_rpc_async("bot_list_community_membership_candidates", {})


async def bot_list_onboarding_restriction_candidates():
    return await call_rpc_async("bot_list_onboarding_restriction_candidates", {})


async def bot_set_onboarding_restriction_state(tg_id, restricted, notified=False):
    # This RPC only persists the current onboarding state, so retrying transient
    # connection failures is safe and prevents one dropped HTTP connection from
    # leaving Telegram permissions and our DB state out of sync.
    return await call_rpc_async(
        "bot_set_onboarding_restriction_state",
        {
            "p_tg_id": tg_id,
            "p_restricted": restricted,
            "p_notified": notified,
        },
        retries=3,
    )

async def bot_submit_application(tg_id, username, full_name, birth_date, minecraft_nick, platform, goal, about, discovery_source):
    return await call_rpc_async("bot_submit_application_v2", {
        "p_tg_id": tg_id,
        "p_username": username,
        "p_full_name": full_name,
        "p_birth_date": birth_date,
        "p_minecraft_nick": minecraft_nick,
        "p_platform": platform,
        "p_goal": goal,
        "p_about": about,
        "p_discovery_source": discovery_source,
    })

async def bot_change_minecraft_nick(tg_id, new_nick):
    return await call_rpc_async("bot_change_minecraft_nick", {"p_tg_id": tg_id, "p_new_nick": new_nick})

async def bot_check_admin_permission(tg_id, permission_key):
    return await call_rpc_async("bot_check_admin_permission", {"p_tg_id": tg_id, "p_permission_key": permission_key})

    
async def bot_get_staff_context(tg_id):
    return await call_rpc_async("bot_get_staff_context", {"p_tg_id": tg_id})

async def bot_get_profile(tg_id):
    return await call_rpc_async("bot_get_profile", {"p_tg_id": tg_id})


async def bot_get_minecraft_auth_status(tg_id):
    return await call_rpc_async("bot_get_minecraft_auth_status", {"p_tg_id": tg_id})


async def bot_get_player_stats(tg_id):
    return await call_rpc_async("bot_get_player_stats", {"p_tg_id": tg_id})

async def bot_get_player_activity_stats(tg_id):
    return await call_rpc_async("bot_get_player_activity_stats", {"p_tg_id": tg_id})


async def bot_get_achievements(tg_id):
    return await call_rpc_async("bot_get_achievements", {"p_tg_id": tg_id})


async def bot_get_own_punishments(tg_id):
    return await call_rpc_async("bot_get_own_punishments", {"p_tg_id": tg_id})


async def bot_get_player_reports(tg_id):
    return await call_rpc_async("bot_get_player_reports", {"p_tg_id": tg_id})


async def bot_get_notification_preferences(tg_id):
    return await call_rpc_async("bot_get_notification_preferences", {"p_tg_id": tg_id})


async def bot_get_community_chat_id():
    return await call_rpc_async("bot_get_community_chat_id", {})


async def bot_bridge_enqueue_from_telegram(chat_id, message_id, telegram_user_id, sender_name, message):
    return await call_rpc_async("bot_bridge_enqueue_from_telegram", {
        "p_chat_id": chat_id,
        "p_message_id": message_id,
        "p_telegram_user_id": telegram_user_id,
        "p_sender_name": sender_name,
        "p_message": message,
    }, retries=2, retry_delay_seconds=0.5)


async def bot_bridge_claim_for_telegram(limit=20):
    return await call_rpc_async("mc_bridge_claim_for_telegram", {"p_limit": limit})


async def bot_bridge_finish_message(message_id, lease_token, status, error=None, retry_after_seconds=5):
    return await call_rpc_async("mc_bridge_finish_message", {
        "p_message_id": message_id,
        "p_lease_token": lease_token,
        "p_status": status,
        "p_error": error,
        "p_retry_after_seconds": retry_after_seconds,
    })


async def bot_claim_notifications(limit=20):
    return await call_rpc_async("bot_claim_notifications", {"p_limit": limit})


async def bot_get_notification_preference(user_id, key):
    return await call_rpc_async("bot_get_notification_preference", {
        "p_user_id": user_id,
        "p_key": key,
    })


async def bot_finish_notification(notification_id, status, error=None, retry_after_seconds=None):
    return await call_rpc_async("bot_finish_notification", {
        "p_notification_id": notification_id,
        "p_status": status,
        "p_error": error,
        "p_retry_after_seconds": retry_after_seconds,
    })


async def bot_mark_support_message_delivery(message_id, status, error=None):
    return await call_rpc_async("bot_mark_support_message_delivery", {
        "p_message_id": message_id,
        "p_status": status,
        "p_error": error,
    })


async def bot_set_notification_preference(tg_id, key, enabled):
    return await call_rpc_async("bot_set_notification_preference", {
        "p_tg_id": tg_id,
        "p_key": key,
        "p_enabled": enabled,
    })


async def bot_get_player_appeals(tg_id):
    return await call_rpc_async("bot_get_player_appeals", {"p_tg_id": tg_id})


async def bot_get_server_metrics():
    return await call_rpc_async("bot_get_server_metrics", {})


async def bot_get_online_players():
    return await call_rpc_async("bot_get_online_players", {})


async def bot_get_leaderboard(field="rating", limit=10):
    return await call_rpc_async("bot_get_leaderboard", {
        "p_field": field,
        "p_limit": limit,
    })

async def bot_get_clan_info(tg_id):
    return await call_rpc_async("bot_get_clan_info", {"p_tg_id": tg_id})

async def bot_create_clan(tg_id, name):
    return await call_rpc_async("bot_create_clan", {"p_tg_id": tg_id, "p_name": name})

async def bot_create_report(reporter_tg_id, target_tg_id, reason):
    return await call_rpc_async("bot_create_report", {"p_reporter_tg_id": reporter_tg_id, "p_target_tg_id": target_tg_id, "p_reason": reason})

async def bot_get_user_status(tg_id):
    result = await bot_get_profile(tg_id)
    if result.error:
        return "ERROR"
    if not isinstance(result.data, dict):
        return "ERROR"
    if result.data.get("error") == "USER_NOT_FOUND":
        return "NO_USER"

    user_status = str(result.data.get("status") or "").upper()
    application_status = str(result.data.get("application_status") or "").upper()

    # A Telegram group sighting creates a lightweight PENDING user row with no
    # application. That must remain eligible to apply; only a real application
    # can block onboarding.
    if application_status in {"PENDING", "ACCEPTED"}:
        return application_status
    if user_status == "ACCEPTED":
        return "ACCEPTED"
    if user_status == "REJECTED":
        return "REJECTED"
    if user_status == "PENDING" and not application_status:
        return "NO_APPLICATION"
    return application_status or "NO_APPLICATION"

async def bot_create_punishment(user_tg_id, p_type, reason, admin_tg_id, duration=None, source_type=None, source_id=None):
    return await call_rpc_async("bot_create_punishment", {
        "p_user_tg_id": user_tg_id, "p_type": p_type, "p_reason": reason,
        "p_admin_tg_id": admin_tg_id, "p_duration": duration,
        "p_source_type": source_type, "p_source_id": source_id,
    })

async def bot_apply_automod_punishment(chat_id, user_tg_id, p_type, reason, duration=None, rule_key="automod", payload=None):
    return await call_rpc_async("bot_apply_automod_punishment", {
        "p_chat_id": chat_id,
        "p_user_tg_id": user_tg_id,
        "p_type": p_type,
        "p_reason": reason,
        "p_duration": duration,
        "p_rule_key": rule_key,
        "p_payload": payload or {},
    })

async def bot_rollback_automod_punishment(punishment_id, error=None):
    return await call_rpc_async("bot_rollback_automod_punishment", {
        "p_punishment_id": punishment_id,
        "p_error": error,
    })

async def bot_lift_punishment(user_tg_id, p_type, admin_tg_id):
    return await call_rpc_async("bot_lift_punishment", {"p_user_tg_id": user_tg_id, "p_type": p_type, "p_admin_tg_id": admin_tg_id})

async def bot_get_punishment_history(user_tg_id, admin_tg_id):
    return await call_rpc_async("bot_get_punishment_history", {"p_user_tg_id": user_tg_id, "p_admin_tg_id": admin_tg_id})

async def bot_get_punishment_by_id(punishment_id):
    return await call_rpc_async("bot_get_punishment_by_id", {"p_punishment_id": punishment_id})

async def bot_approve_application(application_id, admin_tg_id):
    return await call_rpc_async("bot_approve_application", {"p_application_id": application_id, "p_admin_tg_id": admin_tg_id})

async def bot_reject_application(application_id, admin_tg_id, reason=None):
    return await call_rpc_async("bot_reject_application", {
        "p_application_id": application_id,
        "p_admin_tg_id": admin_tg_id,
        "p_reason": reason,
    })

async def bot_set_report_status(report_id, status, admin_tg_id):
    return await call_rpc_async("bot_set_report_status", {
        "p_report_id": report_id,
        "p_status": status,
        "p_admin_tg_id": admin_tg_id,
    })

async def bot_create_chat_punishment(chat_id, user_tg_id, p_type, reason, admin_tg_id, duration=None):
    return await call_rpc_async("bot_create_chat_punishment", {
        "p_chat_id": chat_id,
        "p_user_tg_id": user_tg_id,
        "p_type": p_type,
        "p_reason": reason,
        "p_admin_tg_id": admin_tg_id,
        "p_duration": duration,
    })

async def bot_lift_chat_punishment(chat_id, user_tg_id, p_type, admin_tg_id):
    return await call_rpc_async("bot_lift_chat_punishment", {
        "p_chat_id": chat_id,
        "p_user_tg_id": user_tg_id,
        "p_type": p_type,
        "p_admin_tg_id": admin_tg_id,
    })

async def bot_revoke_chat_punishment(punishment_id, admin_tg_id):
    return await call_rpc_async("bot_revoke_chat_punishment", {
        "p_punishment_id": punishment_id,
        "p_admin_tg_id": admin_tg_id,
    })

async def bot_get_chat_warnings(chat_id, user_tg_id):
    return await call_rpc_async("bot_get_chat_warnings", {
        "p_chat_id": chat_id,
        "p_user_tg_id": user_tg_id,
    })

async def bot_get_chat_mutes(chat_id):
    return await call_rpc_async("bot_get_chat_mutes", {
        "p_chat_id": chat_id,
    })

async def bot_chat_top(chat_id, days=None, limit=10):
    return await call_rpc_async("bot_chat_top", {
        "p_chat_id": chat_id,
        "p_days": days,
        "p_limit": limit,
    })

async def bot_chat_stats(chat_id):
    return await call_rpc_async("bot_chat_stats", {
        "p_chat_id": chat_id,
    })

async def bot_chat_top_total(chat_id, days=None):
    return await call_rpc_async("bot_chat_top_total", {
        "p_chat_id": chat_id,
        "p_days": days,
    })

async def bot_list_current_participants():
    return await call_rpc_async("bot_list_current_participants", {})

async def bot_list_inactive_members(days, limit=100):
    return await call_rpc_async("bot_list_inactive_members", {
        "p_days": days,
        "p_limit": limit,
    })

async def bot_active_chat_users(chat_id, minutes=10, limit=50):
    return await call_rpc_async("bot_active_chat_users", {
        "p_chat_id": chat_id,
        "p_minutes": minutes,
        "p_limit": limit,
    })

async def bot_get_chat_profile_stats(chat_id, tg_id):
    return await call_rpc_async("bot_get_chat_profile_stats", {
        "p_chat_id": chat_id,
        "p_tg_id": tg_id,
    })

async def bot_record_telegram_activity(chat_id, tg_id):
    return await call_rpc_async("bot_record_telegram_activity", {
        "p_chat_id": chat_id,
        "p_tg_id": tg_id,
    })

async def bot_set_staff_role(actor_tg_id, target_tg_id, role_name):
    return await call_rpc_async("bot_set_staff_role", {
        "p_actor_tg_id": actor_tg_id,
        "p_target_tg_id": target_tg_id,
        "p_role_name": role_name,
    })


async def bot_set_staff_rank(actor_tg_id, target_tg_id, rank):
    return await call_rpc_async("bot_set_staff_rank", {
        "p_actor_tg_id": actor_tg_id,
        "p_target_tg_id": target_tg_id,
        "p_rank": rank,
    })

async def bot_remove_staff(actor_tg_id, target_tg_id):
    return await call_rpc_async("bot_remove_staff", {
        "p_actor_tg_id": actor_tg_id,
        "p_target_tg_id": target_tg_id,
    })

async def bot_list_staff():
    return await call_rpc_async("bot_list_staff", {})

async def bot_list_clans():
    return await call_rpc_async("bot_list_clans", {})

async def bot_get_clan_by_position(position):
    return await call_rpc_async("bot_get_clan_by_position", {
        "p_position": position,
    })

async def bot_join_clan(tg_id, name):
    return await call_rpc_async("bot_join_clan", {
        "p_tg_id": tg_id,
        "p_name": name,
    })

async def bot_leave_clan(tg_id):
    return await call_rpc_async("bot_leave_clan", {
        "p_tg_id": tg_id,
    })

async def bot_disband_clan(tg_id):
    return await call_rpc_async("bot_disband_clan", {
        "p_tg_id": tg_id,
    })

async def bot_clan_invite(tg_id, target_nickname):
    return await call_rpc_async("bot_clan_invite", {
        "p_tg_id": tg_id,
        "p_target_nickname": target_nickname,
    })

async def bot_set_clan_role(tg_id, target_nickname, role):
    return await call_rpc_async("bot_set_clan_role", {
        "p_tg_id": tg_id,
        "p_target_nickname": target_nickname,
        "p_role": role,
    })

async def bot_list_clan_invites(tg_id):
    return await call_rpc_async("bot_list_clan_invites", {"p_tg_id": tg_id})

async def bot_accept_clan_invite(tg_id, invite_id):
    return await call_rpc_async("bot_accept_clan_invite", {
        "p_tg_id": tg_id,
        "p_invite_id": invite_id,
    })

async def bot_decline_clan_invite(tg_id, invite_id):
    return await call_rpc_async("bot_decline_clan_invite", {
        "p_tg_id": tg_id,
        "p_invite_id": invite_id,
    })

async def bot_cancel_clan_invite(tg_id, invite_id):
    return await call_rpc_async("bot_cancel_clan_invite", {
        "p_tg_id": tg_id,
        "p_invite_id": invite_id,
    })

async def bot_get_clan_activity(tg_id):
    return await call_rpc_async("bot_get_clan_activity", {"p_tg_id": tg_id})

async def bot_get_clan_achievements(tg_id):
    return await call_rpc_async("bot_get_clan_achievements", {"p_tg_id": tg_id})

async def bot_create_clan_announcement(tg_id, title, body):
    return await call_rpc_async("bot_create_clan_announcement", {
        "p_tg_id": tg_id,
        "p_title": title,
        "p_body": body,
    })

async def bot_list_clan_wars(tg_id):
    return await call_rpc_async("bot_list_clan_wars", {"p_tg_id": tg_id})

async def bot_create_clan_war(tg_id, target):
    return await call_rpc_async("bot_create_clan_war", {
        "p_tg_id": tg_id,
        "p_target": target,
    })

async def bot_respond_clan_war(tg_id, war_id, action):
    return await call_rpc_async("bot_respond_clan_war", {
        "p_tg_id": tg_id,
        "p_war_id": war_id,
        "p_action": action,
    })

async def bot_start_clan_war(tg_id, war_id):
    return await call_rpc_async("bot_start_clan_war", {
        "p_tg_id": tg_id,
        "p_war_id": war_id,
    })

async def bot_finish_clan_war(tg_id, war_id, score_a, score_b):
    return await call_rpc_async("bot_finish_clan_war", {
        "p_tg_id": tg_id,
        "p_war_id": war_id,
        "p_score_a": score_a,
        "p_score_b": score_b,
    })


async def bot_social_request(tg_id, target_tg_id, kind):
    return await call_rpc_async("bot_social_request", {
        "p_tg_id": tg_id,
        "p_target_tg_id": target_tg_id,
        "p_kind": kind,
    })

async def bot_social_info(tg_id):
    return await call_rpc_async("bot_social_info", {
        "p_tg_id": tg_id,
    })

async def bot_social_respond(tg_id, kind, request_id, accept):
    return await call_rpc_async("bot_social_respond", {
        "p_tg_id": tg_id,
        "p_kind": kind,
        "p_request_id": request_id,
        "p_accept": accept,
    })

async def bot_social_cancel(tg_id, kind, request_id):
    return await call_rpc_async("bot_social_cancel", {
        "p_tg_id": tg_id,
        "p_kind": kind,
        "p_request_id": request_id,
    })

async def bot_social_end(tg_id, kind):
    return await call_rpc_async("bot_social_end", {
        "p_tg_id": tg_id,
        "p_kind": kind,
    })

async def bot_list_marriages():
    return await call_rpc_async("bot_list_marriages", {})

async def bot_get_active_punishments():
    return await call_rpc_async("bot_get_active_punishments_for_plugin", {})

async def bot_find_user(identifier: str):
    result = await call_rpc_async("bot_find_user", {"p_identifier": identifier.strip()})
    if result.error: return result
    if isinstance(result.data, dict) and result.data.get("error"): return RPCResult(error=str(result.data["error"]))
    return result

async def bot_create_poll(tg_id, question, description, options, chat_id, allow_multiple=False, max_choices=1, allow_add_options=False, allow_change_vote=True, show_voters=False, expires_at=None, has_correct_answer=False, correct_options=None):
    return await call_rpc_async("bot_create_poll", {
        "p_tg_id": tg_id, "p_question": question, "p_description": description,
        "p_options": options, "p_chat_id": chat_id, "p_allow_multiple": allow_multiple,
        "p_max_choices": max_choices, "p_allow_add_options": allow_add_options,
        "p_allow_change_vote": allow_change_vote, "p_show_voters": show_voters,
        "p_expires_at": expires_at, "p_has_correct_answer": has_correct_answer,
        "p_correct_options": correct_options or [],
    })

async def bot_add_poll_option(poll_id, text, tg_id):
    return await call_rpc_async("bot_add_poll_option", {"p_poll_id": poll_id, "p_text": text, "p_tg_id": tg_id})

async def bot_vote_poll(poll_id, option_id, tg_id):
    return await call_rpc_async("bot_vote_poll", {"p_poll_id": poll_id, "p_option_id": option_id, "p_tg_id": tg_id})

async def bot_rate_server(tg_id, value):
    return await call_rpc_async("bot_rate_server", {"p_tg_id": tg_id, "p_value": value})

async def bot_finish_poll(poll_id, tg_id):
    return await call_rpc_async("bot_finish_poll", {"p_poll_id": poll_id, "p_tg_id": tg_id})

async def bot_get_poll(poll_id, tg_id):
    return await call_rpc_async("bot_get_poll", {"p_poll_id": poll_id, "p_tg_id": tg_id})

async def bot_get_polls(tg_id):
    return await call_rpc_async("bot_get_polls", {"p_tg_id": tg_id})

async def bot_get_poll_for_message(poll_id):
    return await call_rpc_async("bot_get_poll_for_message", {"p_poll_id": poll_id})

async def bot_get_public_wiki(query="", limit=30):
    return await call_rpc_async("get_public_wiki", {"p_query": query, "p_limit": limit})

async def bot_get_news(tg_id):
    return await call_rpc_async("bot_get_news", {"p_tg_id": tg_id})

async def bot_get_pending_count():
    result = await call_rpc_async("bot_get_pending_count", {})
    if result.error: return 0
    if isinstance(result.data, int): return result.data
    if isinstance(result.data, str) and result.data.isdigit(): return int(result.data)
    if isinstance(result.data, dict) and str(result.data.get("count", "")).isdigit(): return int(result.data["count"])
    return 0

async def bot_get_automod_config(chat_id):
    return await call_rpc_async("bot_get_automod_config", {"p_chat_id": chat_id})

async def bot_record_automod_event(chat_id, tg_id, rule_key, action, score=None, payload=None):
    return await call_rpc_async("bot_record_automod_event", {
        "p_chat_id": chat_id,
        "p_tg_id": tg_id,
        "p_rule_key": rule_key,
        "p_action": action,
        "p_score": score,
        "p_payload": payload or {},
    })

async def bot_get_server_status():
    return await call_rpc_async("bot_get_server_status", {})

async def bot_start_battle(tg_id, opponent_nickname):
    return await call_rpc_async("bot_start_battle", {
        "p_tg_id": tg_id,
        "p_opponent_nickname": opponent_nickname,
    })


async def bot_get_battles(tg_id, limit=10):
    return await call_rpc_async("bot_get_battles", {
        "p_tg_id": tg_id,
        "p_limit": limit,
    })


async def bot_list_events(tg_id, limit=20):
    return await call_rpc_async("bot_list_events", {"p_tg_id": tg_id, "p_limit": limit})

async def bot_register_event(tg_id, event_id):
    return await call_rpc_async("bot_register_event", {
        "p_tg_id": tg_id,
        "p_event_id": event_id,
    })

async def bot_unregister_event(tg_id, event_id):
    return await call_rpc_async("bot_unregister_event", {
        "p_tg_id": tg_id,
        "p_event_id": event_id,
    })

async def bot_consume_login_code(session_token: str, tg_id: int):
    return await call_rpc_async("bot_consume_login_code", {"p_session_token": session_token, "p_tg_id": tg_id})


async def bot_create_appeal(tg_id: int, reason: str, punishment_id=None):
    return await call_rpc_async("bot_create_appeal", {
        "p_tg_id": tg_id,
        "p_reason": reason,
        "p_punishment_id": punishment_id,
    })


async def bot_list_pending_applications(admin_tg_id: int, limit=10):
    return await call_rpc_async("bot_list_pending_applications", {
        "p_admin_tg_id": admin_tg_id,
        "p_limit": limit,
    })


async def bot_list_open_reports(admin_tg_id: int, limit=15):
    return await call_rpc_async("bot_list_open_reports", {
        "p_admin_tg_id": admin_tg_id,
        "p_limit": limit,
    })


async def bot_search_players(admin_tg_id: int, query: str, limit=10):
    return await call_rpc_async("bot_search_players", {
        "p_admin_tg_id": admin_tg_id,
        "p_query": query,
        "p_limit": limit,
    })


async def bot_list_appeals(admin_tg_id: int, status="OPEN", limit=50):
    return await call_rpc_async("bot_list_appeals", {
        "p_admin_tg_id": admin_tg_id,
        "p_status": status,
        "p_limit": limit,
    })


async def bot_manage_appeal(appeal_id, action, admin_tg_id: int, note=None):
    return await call_rpc_async("bot_manage_appeal", {
        "p_appeal_id": appeal_id,
        "p_action": action,
        "p_admin_tg_id": admin_tg_id,
        "p_note": note,
    })


async def bot_claim_onboarding_reminders(limit=20):
    return await call_rpc_async("bot_claim_onboarding_reminders", {"p_limit": limit})


async def bot_get_market(tg_id, kind=None, query="", limit=20):
    return await call_rpc_async("bot_get_market", {
        "p_tg_id": tg_id,
        "p_kind": kind,
        "p_query": query,
        "p_limit": limit,
    })


async def bot_get_market_inquiries(tg_id):
    return await call_rpc_async("bot_get_market_inquiries", {
        "p_tg_id": tg_id,
    })


async def bot_create_market_listing(tg_id, kind, title, description=None, price_text=None, terms=None, expires_at=None):
    return await call_rpc_async("bot_create_market_listing", {
        "p_tg_id": tg_id,
        "p_kind": kind,
        "p_title": title,
        "p_description": description,
        "p_price_text": price_text,
        "p_terms": terms,
        "p_expires_at": expires_at,
    })


async def bot_update_market_listing(tg_id, listing_id, kind, title, description=None, price_text=None, terms=None, expires_at=None):
    return await call_rpc_async("bot_update_market_listing", {
        "p_tg_id": tg_id,
        "p_listing_id": listing_id,
        "p_kind": kind,
        "p_title": title,
        "p_description": description,
        "p_price_text": price_text,
        "p_terms": terms,
        "p_expires_at": expires_at,
    })


async def bot_create_market_offer(tg_id, listing_id, price, note=None):
    return await call_rpc_async("bot_create_market_offer", {
        "p_tg_id": tg_id, "p_listing_id": listing_id, "p_price": price, "p_note": note,
    })


async def bot_respond_market_offer(tg_id, offer_id, action, price=None, note=None):
    return await call_rpc_async("bot_respond_market_offer", {
        "p_tg_id": tg_id, "p_offer_id": offer_id, "p_action": action, "p_price": price, "p_note": note,
    })


async def bot_withdraw_market_offer(tg_id, offer_id):
    return await call_rpc_async("bot_withdraw_market_offer", {"p_tg_id": tg_id, "p_offer_id": offer_id})


async def bot_get_market_offers(tg_id):
    return await call_rpc_async("bot_get_market_offers", {"p_tg_id": tg_id})


async def bot_create_market_inquiry(tg_id, listing_id, message):
    return await call_rpc_async("bot_create_market_inquiry", {
        "p_tg_id": tg_id,
        "p_listing_id": listing_id,
        "p_message": message,
    })


async def bot_respond_market_inquiry(tg_id, inquiry_id, response):
    return await call_rpc_async("bot_respond_market_inquiry", {
        "p_tg_id": tg_id,
        "p_inquiry_id": inquiry_id,
        "p_response": response,
    })


async def bot_close_market_inquiry(tg_id, inquiry_id):
    return await call_rpc_async("bot_close_market_inquiry", {
        "p_tg_id": tg_id,
        "p_inquiry_id": inquiry_id,
    })


async def bot_close_market_listing(tg_id, listing_id):
    return await call_rpc_async("bot_close_market_listing", {
        "p_tg_id": tg_id,
        "p_listing_id": listing_id,
    })


async def bot_rate_prisma(tg_id, value):
    return await call_rpc_async("bot_rate_prisma", {"p_tg_id": tg_id, "p_value": value})

async def bot_get_prisma_rating(tg_id=None):
    return await call_rpc_async("bot_get_prisma_rating", {"p_tg_id": tg_id})

async def bot_create_support_request(tg_id, message):
    return await call_rpc_async("bot_create_support_request", {"p_tg_id": tg_id, "p_message": message})

async def bot_list_support_requests(admin_tg_id, status="OPEN", limit=30):
    return await call_rpc_async("bot_list_support_requests", {"p_admin_tg_id": admin_tg_id, "p_status": status, "p_limit": limit})

async def bot_manage_support_request(admin_tg_id, ticket_no, status, note=None):
    return await call_rpc_async("bot_manage_support_request", {"p_admin_tg_id": admin_tg_id, "p_ticket_no": ticket_no, "p_status": status, "p_note": note})


async def bot_claim_onboarding_digest(limit=100, force=False):
    return await call_rpc_async("bot_claim_onboarding_digest", {
        "p_limit": limit,
        "p_force": force,
    })


async def bot_ai_log_message(tg_id, chat_id, role, content, answer_id=None, agent=False):
    return await call_rpc_async("bot_ai_log_message", {
        "p_tg_id": tg_id, "p_chat_id": chat_id, "p_role": role,
        "p_content": content, "p_answer_id": answer_id, "p_agent": agent,
    })


async def bot_ai_recent(tg_id, chat_id, limit=16):
    return await call_rpc_async("bot_ai_recent", {"p_tg_id": tg_id, "p_chat_id": chat_id, "p_limit": limit})


async def bot_ai_rate(tg_id, answer_id, rating):
    return await call_rpc_async("bot_ai_rate", {"p_tg_id": tg_id, "p_answer_id": answer_id, "p_rating": rating})


async def bot_ai_feedback_stats(days=7):
    return await call_rpc_async("bot_ai_feedback_stats", {"p_days": days})


async def bot_create_market_review(tg_id, offer_id, rating, comment=None):
    return await call_rpc_async("bot_create_market_review", {
        "p_tg_id": tg_id, "p_offer_id": offer_id, "p_rating": rating, "p_comment": comment,
    })


async def bot_my_reviewable_offers(tg_id):
    return await call_rpc_async("bot_my_reviewable_offers", {"p_tg_id": tg_id})


async def bot_market_reputation(nick):
    return await call_rpc_async("bot_market_reputation", {"p_nick": nick})


async def bot_market_risk_data(hours=72):
    return await call_rpc_async("bot_market_risk_data", {"p_hours": hours})


async def bot_create_reminder(tg_id, text, at_iso):
    return await call_rpc_async("bot_create_reminder", {"p_tg_id": tg_id, "p_text": text, "p_at": at_iso})


async def bot_list_reminders(tg_id):
    return await call_rpc_async("bot_list_reminders", {"p_tg_id": tg_id})


async def bot_cancel_reminder(tg_id, reminder_id):
    return await call_rpc_async("bot_cancel_reminder", {"p_tg_id": tg_id, "p_id": reminder_id})


# --- one profile, several accounts (Java + Bedrock, second Telegram account) ---
async def bot_add_minecraft_account(tg_id, platform, nickname):
    return await call_rpc_async("bot_add_minecraft_account", {"p_tg_id": tg_id, "p_platform": platform, "p_nickname": nickname})


async def bot_remove_minecraft_account(tg_id):
    return await call_rpc_async("bot_remove_minecraft_account", {"p_tg_id": tg_id})


async def bot_list_minecraft_accounts(tg_id):
    return await call_rpc_async("bot_list_minecraft_accounts", {"p_tg_id": tg_id})


async def bot_telegram_alias_create(primary_tg, alias_tg):
    return await call_rpc_async("bot_telegram_alias_create", {"p_primary_tg": primary_tg, "p_alias_tg": alias_tg})


async def bot_telegram_alias_resolve(tg_id):
    return await call_rpc_async("bot_telegram_alias_resolve", {"p_tg": tg_id})


async def bot_telegram_alias_remove(primary_tg):
    return await call_rpc_async("bot_telegram_alias_remove", {"p_primary_tg": primary_tg})
