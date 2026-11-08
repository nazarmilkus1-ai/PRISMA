export * from "./labels";

import { MODULE_IDS as GENERATED_MODULE_IDS, MODULE_METADATA as GENERATED_MODULE_METADATA, type ModuleId as GeneratedModuleId } from "./modules.generated";

export const MODULE_IDS = GENERATED_MODULE_IDS;
export type ModuleId = GeneratedModuleId;
export const MODULE_METADATA = GENERATED_MODULE_METADATA;

export type PublicModuleState = {
  module_id: ModuleId;
  enabled: boolean;
};

export type StaffModuleState = PublicModuleState & {
  reason: string | null;
  updated_by: string | null;
  updated_at: string;
};

export const MODULE_STATE_RPC = {
  get: "get_public_module_state",
  list: "get_public_module_states",
} as const;

export const STAFF_MODULE_RPC = {
  list: "staff_get_module_states",
  set: "staff_set_module_state",
} as const;

export { isModuleEffectivelyEnabled } from "./module-runtime";
export type { ModuleEnabledMap } from "./module-runtime";

export const PARTICIPANT_CURRENT_USER_RPC = {
  get: "participant_get_current_user",
} as const;

export const PARTICIPANT_SERVER_ROLE_RPC = {
  get: "participant_get_server_role",
} as const;

export type ParticipantCurrentUser = {
  id: string;
  telegram_username: string | null;
  first_name: string | null;
  last_name: string | null;
  full_name: string | null;
  age: number | null;
  minecraft_nickname: string | null;
  platform: Platform | null;
  status: string;
  is_whitelisted: boolean;
  is_banned: boolean;
  ban_reason: string | null;
  is_muted: boolean;
  muted_until: string | null;
  rating: number;
  activity_score: number;
  level: number;
  xp: number;
  last_login_at: string | null;
  created_at: string;
  clan_id: string | null;
  locale: string | null;
  birth_date: string | null;
  profile_links: Record<string, string> | null;
  social_visibility: SocialVisibility | null;
};

export const PARTICIPANT_RPC = {
  dashboard: "participant_get_dashboard",
  application: "participant_get_application",
  notifications: "participant_get_notifications",
} as const;

export type ParticipantApplication = Omit<Application, "user_id">;

export type ParticipantDashboard = {
  user: {
    id: string;
    telegram_username: string | null;
    first_name: string | null;
    last_name: string | null;
    full_name: string | null;
    age: number | null;
    minecraft_nickname: string | null;
    platform: Platform | null;
    status: string;
    is_whitelisted: boolean;
    is_banned: boolean;
    ban_reason: string | null;
    is_muted: boolean;
    muted_until: string | null;
    rating: number;
    activity_score: number;
    level: number;
    xp: number;
    last_seen_at: string | null;
    last_login_at: string | null;
    created_at: string;
    clan_id: string | null;
    locale: string | null;
    profile_links: Record<string, string> | null;
    social_visibility: SocialVisibility | null;
  } | null;
  application: ParticipantApplication | null;
  reports: PlayerReport[];
  notifications: Notification[];
  preferences: Record<string, boolean> | null;
  clan: unknown | null;
  membership: unknown | null;
  invitations: unknown[];
  clanInvites: {
    incoming: unknown[];
    outgoing: unknown[];
  };
  stats: PlayerStats | null;
  achievements: unknown[];
  polls: unknown[];
};

export const APPLICATION_DISCOVERY_SOURCES = [
  "Telegram",
  "TikTok",
  "YouTube",
  "Discord",
  "Рекомендация друга",
  "Другое",
] as const;

export type ApplicationDiscoverySource = (typeof APPLICATION_DISCOVERY_SOURCES)[number];
export type ApplicationStatus = "PENDING" | "ACCEPTED" | "REJECTED";
export type Platform = "JAVA" | "BEDROCK";

export type SocialVisibility = "PRIVATE" | "PUBLIC";

export type PublicSocialProfile = {
  visibility: SocialVisibility;
  marriage?: {
    partner_nickname: string;
    married_at: string;
  } | null;
  relationship?: {
    partner_nickname: string;
    started_at: string;
  } | null;
};

export type PlayerStats = {
  user_id: string;
  kills: number;
  deaths: number;
  playtime_minutes: number;
  blocks_placed: number;
  blocks_broken: number;
  mobs_killed: number;
  distance_walked: number;
  damage_dealt: number;
  damage_taken: number;
  updated_at: string | null;
};

export type PlayerPassport = {
  user: {
    id: string;
    minecraft_nickname: string;
    platform: Platform | null;
    rating: number;
    activity_score: number;
    level: number;
    xp: number;
    last_seen_at: string | null;
    created_at: string;
    clan_id: string | null;
    profile_links: Record<string, string>;
  };
  stats: PlayerStats;
  achievements: unknown[];
  activity: unknown[];
  clan: unknown | null;
  membership: {
    role: ClanRole | string;
    joined_at: string | null;
    status: string;
  } | null;
  rating_history: Array<{
    rating: number;
    delta: number;
    reason: string;
    created_at: string;
  }>;
  server_role: string;
  social: PublicSocialProfile;
};

export type Application = {
  id: string;
  application_no: number;
  user_id: string;
  full_name: string;
  birth_date: string | null;
  age: number;
  nickname: string;
  platform: Platform;
  discovery_source: ApplicationDiscoverySource | null;
  goal: string | null;
  about: string | null;
  status: ApplicationStatus;
  rejection_reason: string | null;
  cooldown_until: string | null;
  reviewed_at: string | null;
  reviewed_by_tg_id?: number | null;
  reviewed_by_name?: string | null;
  created_at: string;
  updated_at: string;
};

export const APPLICATION_STATUS_LABELS: Record<ApplicationStatus, string> = {
  PENDING: "На рассмотрении",
  ACCEPTED: "Принята",
  REJECTED: "Отклонена",
};

export const CLAN_ROLES = ["owner", "co_owner", "officer", "member", "recruit"] as const;
export type ClanRole = (typeof CLAN_ROLES)[number];

export const CLAN_ROLE_LABELS: Record<ClanRole, string> = {
  owner: "Владелец",
  co_owner: "Совладелец",
  officer: "Офицер",
  member: "Участник",
  recruit: "Рекрут",
};

export const CLAN_ROLE_LEVELS: Record<ClanRole, number> = {
  owner: 50,
  co_owner: 40,
  officer: 30,
  member: 20,
  recruit: 10,
};


export const MODERATION_TYPES = [
  "WARN",
  "MUTE",
  "KICK",
  "BAN",
  "UNMUTE",
  "UNWARN",
  "UNBAN",
  "WHITELIST",
  "UNWHITELIST",
] as const;

export type ModerationType = (typeof MODERATION_TYPES)[number];

export type ModerationLog = {
  id: string;
  target_id: string;
  type: ModerationType | string;
  reason: string;
  duration_minutes: number | null;
  expires_at: string | null;
  source: string | null;
  issued_by_tg_id: number | null;
  issued_by_name: string | null;
  created_at: string;
  applied_at: string | null;
  revoked: boolean;
  revoked_at: string | null;
  revoked_by_tg_id: number | null;
  revoked_by_name: string | null;
  status: string;
};

export const APPEAL_STATUSES = [
  "OPEN",
  "IN_REVIEW",
  "APPROVED",
  "REJECTED",
] as const;

export type AppealStatus = (typeof APPEAL_STATUSES)[number];

export type Appeal = {
  id: string;
  user_id: string;
  telegram_id: number;
  punishment_id: string | null;
  reason: string;
  status: AppealStatus;
  reviewed_by_tg_id: number | null;
  review_note: string | null;
  created_at: string;
  updated_at: string;
  punishment?: Pick<
    ModerationLog,
    "id" | "type" | "reason" | "duration_minutes" | "expires_at" | "revoked" | "status"
  > | null;
};

export const REPORT_STATUSES = [
  "OPEN",
  "IN_REVIEW",
  "RESOLVED",
  "DISMISSED",
] as const;

export type ReportStatus = (typeof REPORT_STATUSES)[number];

export const STAFF_MINECRAFT_AUTH_RPC = {
  status: "staff_get_minecraft_auth_status",
} as const;

export const MINECRAFT_CHAT_BRIDGE_RPC = {
  enqueueFromMinecraft: "mc_bridge_enqueue_from_minecraft",
  claimForMinecraft: "mc_bridge_claim_for_minecraft",
  finishMessage: "mc_bridge_finish_message",
  enqueueFromTelegram: "bot_bridge_enqueue_from_telegram",
  claimForTelegram: "mc_bridge_claim_for_telegram",
} as const;

export const STAFF_RPC = {
  authContext: "staff_get_auth_context",
  authSecurity: "staff_get_auth_security",
  dashboardOverview: "staff_get_dashboard_overview",
  adminRegistry: "staff_get_admin_registry",
  manageAdmin: "staff_manage_admin",
  applications: "staff_list_applications",
  application: "staff_get_application",
  decideApplication: "staff_decide_application",
  appeals: "staff_list_appeals",
  appeal: "staff_get_appeal",
  manageAppeal: "staff_manage_appeal",
  reports: "staff_list_reports",
  report: "staff_get_report",
  reportStats: "staff_report_stats",
  updateReport: "staff_update_report",
  players: "staff_list_players",
  player360: "staff_get_player_360",
  moderationSearchPlayers: "staff_search_moderation_players",
  moderationPlayer: "staff_get_moderation_player",
  applyModeration: "staff_apply_moderation",
  revokeModeration: "staff_revoke_moderation",
  clans: "staff_list_clans",
  clanMemberRole: "staff_update_clan_member_role",
  events: "staff_list_events",
  manageEvent: "staff_manage_event",
  setEventResult: "staff_set_event_result",
  market: "staff_get_market",
  marketInquiries: "staff_get_market_inquiries",
  manageMarket: "staff_manage_market",
  news: "staff_list_news",
  manageNews: "staff_manage_news",
  polls: "staff_list_polls",
  createPoll: "staff_create_poll",
  managePoll: "staff_manage_poll",
  notifications: "staff_list_notifications",
  monitoring: "staff_get_monitoring",
  onboarding: "staff_get_onboarding",
  onboardingBroadcast: "staff_broadcast_onboarding",
  supportTickets: "staff_list_support_tickets",
  supportTicket: "staff_get_support_ticket",
  replySupport: "staff_reply_support_ticket",
  setSupportStatus: "staff_set_support_ticket_status",
  searchSupportRecipients: "staff_search_support_recipients",
  createSupportTicket: "staff_create_support_ticket",
  analytics: "staff_get_analytics",
  analyticsDetails: "staff_get_analytics_details",
  analyticsAdminSummary: "staff_get_analytics_admin_summary",
  auditLogs: "staff_get_audit_logs",
  securitySnapshot: "staff_get_security_snapshot",
  enqueueNotification: "staff_enqueue_notification",
  communityChatId: "staff_get_community_chat_id",
  chatSettings: "staff_get_chat_settings",
  manageChatSettings: "staff_manage_chat_settings",
  mapHistory: "staff_get_map_history",
  deleteChatSettings: "staff_delete_chat_settings",
} as const;

export const STAFF_LIVE_RPC = {
  events: "staff_get_live_events",
} as const;

export const PUBLIC_RPC = {
  serverStatus: "get_public_server_status",
  market: "get_public_market",
  polls: "get_public_polls",
  mapData: "get_public_map_data",
  eventDetails: "get_public_event_details",
  news: "get_public_news",
  clans: "get_public_clans",
  seasons: "get_public_seasons",
  events: "get_public_events",
  wiki: "get_public_wiki",
  media: "get_public_media",
  awards: "get_public_awards",
} as const;

export const AUTH_RATE_LIMIT_RPC = {
  consume: "consume_login_rate_limit",
} as const;

export const PARTICIPANT_READ_RPC = {
  application: "participant_get_application",
  listClans: "participant_list_clans",
  searchPlayers: "participant_search_players",
  playerProfile: "participant_get_player_profile",
  publicSocial: "participant_get_public_social",
  globalSearch: "participant_global_search",
  wiki: "participant_get_wiki",
  social: "participant_get_social",
  clan: "participant_get_clan",
  clanActivity: "participant_get_clan_activity",
  analytics: "participant_get_analytics",
  rankings: "participant_get_rankings",
  rankingEntry: "participant_get_ranking_entry",
  seasonLeaderboard: "participant_get_season_leaderboard",
  timeline: "participant_get_timeline",
  market: "participant_get_market",
  marketInquiries: "participant_get_market_inquiries",
  voting: "participant_get_voting",
  calendar: "participant_get_calendar",
} as const;

export type StaffLiveEvent = {
  id: string;
  event_type: string;
  nickname: string | null;
  command: string | null;
  message: string | null;
  world: string | null;
  created_at: string;
};

export const PARTICIPANT_MARKET_RPC = {
  listing: "participant_get_market_listing",
} as const;

export const PARTICIPANT_MARKET_MUTATION_RPC = {
  createListing: "participant_create_market_listing",
  updateListing: "participant_update_market_listing",
  closeListing: "participant_close_market_listing",
  createInquiry: "participant_create_market_inquiry",
  respondInquiry: "participant_respond_market_inquiry",
  closeInquiry: "participant_close_market_inquiry",
} as const;

export const PARTICIPANT_REPORT_RPC = {
  list: "participant_get_reports",
  detail: "participant_get_report",
} as const;

export const PARTICIPANT_APPEAL_RPC = {
  list: "participant_get_appeals",
} as const;

export const PARTICIPANT_SUPPORT_RPC = {
  list: "participant_list_support_tickets",
  get: "participant_get_support_ticket",
  create: "participant_create_support_ticket",
  reply: "participant_reply_support_ticket",
} as const;

export const PARTICIPANT_REPORT_MUTATION_RPC = {
  create: "participant_create_report",
} as const;

export const PARTICIPANT_EVENT_MUTATION_RPC = {
  register: "participant_register_event",
  unregister: "participant_unregister_event",
} as const;

export const PARTICIPANT_POLL_MUTATION_RPC = {
  voteMany: "participant_vote_poll_many",
} as const;

export const PARTICIPANT_NOTIFICATION_MUTATION_RPC = {
  markRead: "participant_mark_notification_read",
  updatePreference: "participant_update_notification_preference",
} as const;

export const PARTICIPANT_MINECRAFT_AUTH_RPC = {
  status: "participant_get_minecraft_auth_status",
  setPassword: "participant_set_minecraft_password",
} as const;

export type MinecraftAuthStatus = {
  ok?: boolean;
  error?: string;
  platform?: Platform | null;
  minecraft_nickname?: string | null;
  configured?: boolean;
  locked_until?: string | null;
  last_login_at?: string | null;
};

export const PARTICIPANT_APPEAL_MUTATION_RPC = {
  create: "participant_create_appeal",
} as const;

export const PARTICIPANT_BATTLE_MUTATION_RPC = {
  create: "participant_start_battle",
} as const;

export const PARTICIPANT_APPLICATION_MUTATION_RPC = {
  submit: "site_submit_application",
} as const;

export const PARTICIPANT_PROFILE_MUTATION_RPC = {
  update: "participant_update_profile",
  updateSocialVisibility: "participant_update_social_visibility",
} as const;

export const PARTICIPANT_SOCIAL_MUTATION_RPC = {
  action: "participant_social_action",
} as const;

export const PARTICIPANT_CLAN_MUTATION_RPC = {
  create: "participant_create_clan",
  join: "participant_join_clan",
  leave: "participant_leave_clan",
  invite: "participant_clan_invite",
  acceptInvite: "participant_clan_invite_accept",
  cancelInvite: "participant_cancel_clan_invite",
  declineInvite: "participant_clan_invite_decline",
  setRole: "participant_set_clan_role",
  action: "participant_clan_action",
  update: "participant_update_clan",
  createAnnouncement: "participant_create_clan_announcement",
  deleteAnnouncement: "participant_delete_clan_announcement",
  respondWar: "participant_respond_clan_war",
  startWar: "participant_start_clan_war",
  finishWar: "participant_finish_clan_war",
  createWar: "participant_create_clan_war",
  cancelWar: "participant_cancel_clan_war",
  createVillage: "participant_create_village",
  deleteVillage: "participant_delete_village",
} as const;


export type ParticipantReportDetail = {
  report: Pick<
    PlayerReport,
    "id" | "ticket_no" | "type" | "target_nickname" | "description" | "status" |
    "priority" | "category" | "created_at" | "updated_at" | "resolved_at"
  > & {
    occurred_at: string | null;
  };
  history: Array<{
    id: string;
    from_status: string | null;
    to_status: string;
    created_at: string;
  }>;
};

export type PlayerReport = {
  id: string;
  ticket_no: number | string;
  type: string;
  target_nickname: string | null;
  description: string;
  status: ReportStatus | string;
  priority: number | string | null;
  category: string | null;
  created_at: string;
  updated_at?: string | null;
  resolved_at?: string | null;
  assigned_to?: string | null;
};

export const PARTICIPANT_NOTIFICATION_COUNT_RPC = {
  unread: "participant_get_unread_notification_count",
} as const;

export const PARTICIPANT_NOTIFICATION_RPC = {
  preferences: "participant_get_notification_preferences",
} as const;

export const PARTICIPANT_BATTLE_RPC = {
  list: "participant_get_battles",
} as const;

export type ParticipantBattle = {
  id: string;
  challenger_id: string;
  opponent_id: string;
  challenger_score: number;
  opponent_score: number;
  winner_id: string | null;
  points_awarded: number;
  status: string;
  created_at: string;
  challenger: { minecraft_nickname: string | null };
  opponent: { minecraft_nickname: string | null };
  winner: { minecraft_nickname: string | null } | null;
};

export const NOTIFICATION_STATUSES = [
  "pending",
  "sending",
  "sent",
  "failed",
  "cancelled",
  "read",
] as const;

export type NotificationStatus = (typeof NOTIFICATION_STATUSES)[number];

export const NOTIFICATION_PREFERENCES = [
  "news",
  "events",
  "server_status",
  "clan_news",
  "social",
  "battles",
  "market",
  "moderation",
  "polls",
] as const;

export type NotificationPreference = (typeof NOTIFICATION_PREFERENCES)[number];

export type Notification = {
  id: string;
  user_id: string | null;
  telegram_id: number | null;
  channel: string;
  kind: string;
  title: string | null;
  body: string;
  data: Record<string, unknown>;
  status: NotificationStatus | string;
  attempts: number;
  last_error: string | null;
  created_at: string;
  sent_at: string | null;
  updated_at: string;
};

export const MARKET_LISTING_KINDS = [
  "SELL",
  "BUY",
  "TRADE",
  "SERVICE",
  "OTHER",
] as const;

export type MarketListingKind = (typeof MARKET_LISTING_KINDS)[number];
export type MarketListingStatus = "ACTIVE" | "CLOSED" | "EXPIRED";
export type MarketInquiryStatus = "OPEN" | "ANSWERED" | "CLOSED";

export type MarketListing = {
  id: string;
  seller_id: string;
  kind: MarketListingKind | string;
  title: string;
  description: string | null;
  terms: string | null;
  price_text: string | null;
  status: MarketListingStatus | string;
  created_at: string;
  updated_at: string;
  expires_at: string | null;
};

export type MarketInquiry = {
  id: string;
  listing_id: string;
  requester_id: string;
  seller_id: string;
  message: string;
  response: string | null;
  status: MarketInquiryStatus | string;
  created_at: string;
  updated_at: string;
  responded_at: string | null;
  closed_at: string | null;
};

export {
  MINECRAFT_COMMAND_CATALOG,
  MINECRAFT_COMMANDS,
  MINECRAFT_ROLES,
  MINECRAFT_AUTHENTICATION,
  MINECRAFT_CLAN_WAR_SUBCOMMANDS,
} from "./minecraft-commands";

export type {
  MinecraftCommand,
  MinecraftRole,
  MinecraftAuthentication,
} from "./minecraft-commands";
