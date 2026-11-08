"""PRISMA community rules. Keep in sync with site/src/app/rules/page.tsx."""

RULES = (
    ("Уважение", "Не мешайте другим игрокам, не провоцируйте конфликты и соблюдайте решения модерации."),
    ("Честная игра", "Не используйте читы, эксплойты и другие способы получения нечестного преимущества."),
    ("Сообщество", "Сохраняйте нормальную атмосферу в Telegram и на сервере."),
    ("Контент", "Не распространяйте запрещённый или опасный контент через инфраструктуру PRISMA."),
)


def rules_text() -> str:
    from html import escape

    blocks = [f"<b>{n}. {escape(title)}</b>\n{escape(body)}" for n, (title, body) in enumerate(RULES, 1)]
    footer = "Нарушения ведут к предупреждению, муту или бану. Спорное решение можно оспорить через апелляцию."
    return "📜 <b>Правила PRISMA</b>\n\n" + "\n\n".join(blocks) + "\n\n" + footer
