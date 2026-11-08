export const EVENT_STATUS_LABELS: Record<string, string> = {
  draft: "Черновик",
  scheduled: "Запланировано",
  live: "Идёт сейчас",
  finished: "Завершено",
  cancelled: "Отменено",
  published: "Опубликовано",
};

export const NOTIFICATION_STATUS_LABELS: Record<string, string> = {
  pending: "Ожидает",
  sending: "Отправляется",
  sent: "Доставлено",
  read: "Прочитано",
  failed: "Ошибка",
  cancelled: "Отменено",
};

export const REPORT_STATUS_LABELS: Record<string, string> = {
  OPEN: "Открыто",
  IN_REVIEW: "В работе",
  RESOLVED: "Решено",
  DISMISSED: "Отклонено",
};

export const REPORT_TYPE_LABELS: Record<string, string> = {
  PLAYER: "Игрок",
  BUG: "Ошибка",
  SERVER: "Сервер",
};

export const APPEAL_STATUS_LABELS: Record<string, string> = {
  OPEN: "Открыта",
  IN_REVIEW: "В работе",
  APPROVED: "Одобрена",
  REJECTED: "Отклонена",
};

export const SUPPORT_TICKET_STATUS_LABELS: Record<string, string> = {
  OPEN: "Открыт",
  IN_REVIEW: "В работе",
  RESOLVED: "Решён",
  CLOSED: "Закрыт",
};

export const MARKET_LISTING_STATUS_LABELS: Record<string, string> = {
  ACTIVE: "Активно",
  CLOSED: "Закрыто",
  EXPIRED: "Истекло",
};

export const MARKET_LISTING_KIND_LABELS: Record<string, string> = {
  SELL: "Продам",
  BUY: "Куплю",
  TRADE: "Обмен",
  SERVICE: "Услуга",
  OTHER: "Другое",
};

export const CLAN_ENTITY_STATUS_LABELS: Record<string, string> = {
  active: "Активен",
  deleted: "Удалён",
  pending: "Ожидает",
  accepted: "Принято",
  declined: "Отклонено",
  expired: "Истёк",
  scheduled: "Запланирована",
  finished: "Завершена",
  cancelled: "Отменена",
};

export const STAFF_ROLE_LABELS: Record<string, string> = {
  owner: "10 · Owner",
  head_admin: "9 · Co-Owner / Head Admin",
  head_staff: "8 · Head of Staff / Head Mod",
  admin: "7 · Administrator",
  senior_moderator: "6 · Senior Moderator",
  moderator: "5 · Moderator",
  helper: "4 · Helper / Trainee",
  developer: "3 · Developer / Tech Admin",
  builder: "2 · Builder / Map Maker",
  game_designer: "2 · Game Designer / Content Creator",
  event_manager: "2 · Event Manager",
  media: "1 · Media / Blogger",
  content_maker: "1 · Legacy Content Maker",
};

export const SEASON_STATUS_LABELS: Record<string, string> = {
  active: "Активен",
  ACTIVE: "Активно",
  UPCOMING: "Скоро",
  FINISHED: "Завершён",
};

export const CLAN_TYPE_LABELS: Record<string, string> = {
  open: "Открытый",
  closed: "Закрытый",
  private: "Закрытый",
};
