// AUTO-GENERATED from modules/registry.json. Do not edit by hand.
export const MODULE_IDS = [
  "auth",
  "applications",
  "players",
  "battles",
  "moderation",
  "reports",
  "appeals",
  "clans",
  "events",
  "market",
  "voting",
  "notifications",
  "social",
  "map",
  "chat",
  "analytics",
  "audit-security",
  "minecraft",
  "public-content",
  "staff-core",
  "minecraft-teleport-requests",
  "minecraft-homes",
  "minecraft-spawns",
  "minecraft-journey",
  "minecraft-graves",
  "minecraft-hud",
  "minecraft-moderation",
  "minecraft-tpall",
  "minecraft-staff-teleport",
  "minecraft-clan-commands",
  "minecraft-village-commands",
  "minecraft-village-protection",
  "minecraft-chat-bridge",
  "minecraft-maze-runner"
] as const;

export type ModuleId = (typeof MODULE_IDS)[number];

export const MODULE_METADATA: Record<ModuleId, {
  title: string;
  owner: string;
  status: "planned" | "active" | "deprecated";
  runtimeManaged: boolean;
  runtimeToggleProtected: boolean;
  dependsOn: readonly ModuleId[];
}> = {
  "auth": {
    "title": "Авторизация и идентичность",
    "owner": "platform",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": true,
    "dependsOn": []
  },
  "applications": {
    "title": "Заявки и онбординг",
    "owner": "onboarding",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "auth"
    ]
  },
  "players": {
    "title": "Игроки и профили",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "auth"
    ]
  },
  "battles": {
    "title": "Битвы и рейтинг",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "moderation": {
    "title": "Модерация",
    "owner": "moderation",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "reports": {
    "title": "Репорты игроков",
    "owner": "moderation",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "appeals": {
    "title": "Апелляции",
    "owner": "moderation",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "moderation"
    ]
  },
  "clans": {
    "title": "Кланы, деревни и войны",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "events": {
    "title": "События и календарь",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "market": {
    "title": "Рынок сообщества",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "voting": {
    "title": "Голосования",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "notifications": {
    "title": "Уведомления",
    "owner": "platform",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "auth"
    ]
  },
  "social": {
    "title": "Социальные связи",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "map": {
    "title": "Minecraft-карта и история",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players"
    ]
  },
  "chat": {
    "title": "Настройки community-чата",
    "owner": "community",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "auth"
    ]
  },
  "analytics": {
    "title": "Аналитика и телеметрия",
    "owner": "platform",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "players",
      "events"
    ]
  },
  "audit-security": {
    "title": "Аудит и безопасность",
    "owner": "platform",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "auth"
    ]
  },
  "minecraft": {
    "title": "Minecraft-интеграция",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "auth",
      "players",
      "moderation",
      "clans",
      "events"
    ]
  },
  "public-content": {
    "title": "Публичный контент",
    "owner": "content",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": []
  },
  "staff-core": {
    "title": "Staff control plane",
    "owner": "platform",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": true,
    "dependsOn": [
      "auth"
    ]
  },
  "minecraft-teleport-requests": {
    "title": "Игровая механика: запросы телепортации (/tpa)",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-homes": {
    "title": "Игровая механика: личные дома",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-spawns": {
    "title": "Игровая механика: точки появления",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-journey": {
    "title": "Игровая механика: координаты и контрольные точки",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-graves": {
    "title": "Игровая механика: могилы после смерти",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-hud": {
    "title": "Игровая механика: HUD и TAB",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-moderation": {
    "title": "Игровая механика: команды модерации",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft",
      "moderation"
    ]
  },
  "minecraft-tpall": {
    "title": "Игровая механика: массовая телепортация (/tpall)",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-staff-teleport": {
    "title": "Игровая механика: телепортация персонала",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  },
  "minecraft-clan-commands": {
    "title": "Игровая механика: команды кланов",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft",
      "clans"
    ]
  },
  "minecraft-village-commands": {
    "title": "Игровая механика: команды сёл",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft",
      "clans"
    ]
  },
  "minecraft-village-protection": {
    "title": "Игровая механика: защита территорий сёл",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft",
      "clans"
    ]
  },
  "minecraft-chat-bridge": {
    "title": "Игровая механика: мост чата Minecraft ↔ Telegram",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft",
      "chat"
    ]
  },
  "minecraft-maze-runner": {
    "title": "Игровой режим Maze Runner",
    "owner": "minecraft",
    "status": "active",
    "runtimeManaged": true,
    "runtimeToggleProtected": false,
    "dependsOn": [
      "minecraft"
    ]
  }
} as const;
