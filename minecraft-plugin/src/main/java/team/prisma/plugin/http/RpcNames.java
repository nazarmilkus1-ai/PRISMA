package team.prisma.plugin.http;

/**
 * Canonical PRISMA RPC names used by the Minecraft plugin.
 * Keep transport call sites free of raw RPC strings so migrations and
 * contract reviews have one stable source inside the Java deployable.
 */
public final class RpcNames {
    private RpcNames() {}

    public static final String GET_MINECRAFT_USER = "get_minecraft_user";
    public static final String GET_PUBLIC_MODULE_STATES = "get_public_module_states";
    public static final String GET_MINECRAFT_USER_V2 = "get_minecraft_user_v2";
    public static final String MC_AUTH_STATUS = "mc_auth_status";
    public static final String MC_AUTH_SET_PASSWORD = "mc_auth_set_password";
    public static final String MC_AUTH_LOGIN = "mc_auth_login";
    public static final String MC_AUTH_CHANGE_PASSWORD = "mc_auth_change_password";
    public static final String BIND_MINECRAFT_IDENTITY = "mc_bind_minecraft_identity";
    public static final String CLAIM_PENDING_MODERATION = "mc_claim_pending_moderation";
    public static final String MARK_MODERATION_APPLIED = "mc_mark_moderation_applied";
    public static final String MC_STAFF_APPLY_MODERATION = "mc_staff_apply_moderation";
    public static final String MC_STAFF_LIFT_MODERATION = "mc_staff_lift_moderation";
    public static final String MC_STAFF_MODERATION_HISTORY = "mc_staff_moderation_history";
    public static final String MC_BRIDGE_ENQUEUE_FROM_MINECRAFT = "mc_bridge_enqueue_from_minecraft";
    public static final String MC_BRIDGE_CLAIM_FOR_MINECRAFT = "mc_bridge_claim_for_minecraft";
    public static final String MC_BRIDGE_FINISH_MESSAGE = "mc_bridge_finish_message";
    public static final String UPSERT_PLAYER_STATS = "mc_upsert_player_stats";
    public static final String UPSERT_SERVER_HEARTBEAT = "upsert_server_heartbeat";
    public static final String TOUCH_ONLINE_PLAYERS = "touch_online_players";
    public static final String GET_STAFF_PERMISSION = "mc_get_staff_permission";
    public static final String GET_STAFF_IDENTITY = "mc_get_staff_identity";

    public static final String CREATE_CLAN = "mc_create_clan";
    public static final String JOIN_CLAN = "mc_join_clan";
    public static final String LEAVE_CLAN = "mc_leave_clan";
    public static final String LIST_CLANS = "mc_list_clans";
    public static final String GET_CLAN_BY_IDENTIFIER = "mc_get_clan_by_identifier";
    public static final String INVITE_PLAYER = "mc_invite_player";
    public static final String LIST_CLAN_INVITES = "mc_list_clan_invites";
    public static final String ACCEPT_CLAN_INVITE = "mc_accept_clan_invite";
    public static final String DECLINE_CLAN_INVITE = "mc_decline_clan_invite";
    public static final String SET_CLAN_ROLE = "mc_set_clan_role";
    public static final String CLAN_ACTION = "mc_clan_action";
    public static final String LIST_CLAN_ANNOUNCEMENTS = "mc_list_clan_announcements";
    public static final String CREATE_CLAN_ANNOUNCEMENT = "mc_create_clan_announcement";
    public static final String LIST_CLAN_WARS = "mc_list_clan_wars";
    public static final String CREATE_CLAN_WAR = "mc_create_clan_war";
    public static final String RESPOND_CLAN_WAR = "mc_respond_clan_war";
    public static final String START_CLAN_WAR = "mc_start_clan_war";
    public static final String FINISH_CLAN_WAR = "mc_finish_clan_war";
    public static final String LIST_ACTIVE_VILLAGES = "mc_list_active_villages";
    public static final String CREATE_VILLAGE = "mc_create_village";
    public static final String DELETE_VILLAGE = "mc_delete_village";
    public static final String SET_VILLAGE_RADIUS = "mc_set_village_radius";
    public static final String RECORD_CHAT_MESSAGE = "mc_record_chat_message";
    public static final String RECORD_MINECRAFT_EVENT = "mc_record_minecraft_event";
    public static final String GET_PLAYER_STATS = "mc_get_player_stats";
    public static final String RECORD_ACTIVITY_EVENT = "record_activity_event";
}
