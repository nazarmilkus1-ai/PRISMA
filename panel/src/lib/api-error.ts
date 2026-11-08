import "server-only";

const KNOWN: Record<string, string> = {
  AUTH_REQUIRED: "Требуется авторизация.",
  ADMIN_PROFILE_NOT_LINKED: "Профиль администратора не связан с PRISMA.",
  PERMISSION_DENIED: "Недостаточно прав.",
  FORBIDDEN: "Недостаточно прав.",
  USER_NOT_FOUND: "Профиль PRISMA не найден.",
  PLAYER_NOT_FOUND: "Игрок не найден.",
  APPLICATION_NOT_FOUND: "Заявка не найдена.",
  APPEAL_NOT_FOUND: "Апелляция не найдена.",
  APPEAL_ALREADY_CLOSED: "Апелляция уже закрыта.",
  REPORT_NOT_FOUND: "Репорт не найден.",
  LISTING_NOT_FOUND: "Объявление не найдено.",
  LISTING_REQUIRED: "Не указано объявление.",
  INQUIRY_NOT_FOUND: "Запрос не найден.",
  INQUIRY_REQUIRED: "Не указан запрос.",
  INQUIRY_CLOSED: "Запрос уже закрыт.",
  INVALID_ROLE: "Выбрана некорректная роль.",
  ROLE_UNCHANGED: "У игрока уже установлена эта роль.",
  TARGET_NOT_IN_CLAN: "Игрок не состоит в активном клане.",
  OWNER_PROTECTED: "Владельца клана нельзя изменить этой операцией.",
  INVALID_STATUS: "Некорректный статус.",
};

export function safeApiError(error: unknown, fallback = "Не удалось выполнить действие."): string {
  const message = typeof error === "string" ? error : error instanceof Error ? error.message : "";
  const normalized = message.trim().toUpperCase();
  return KNOWN[normalized] ?? fallback;
}
