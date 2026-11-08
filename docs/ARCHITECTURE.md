# Architecture

## Core rule

**Supabase is the source of truth; shared contracts define component boundaries; consumers adapt those contracts to their own user experience.**

PRISMA is not a collection of independent apps. The Telegram bot, participant website, staff dashboard, and Paper plugin share identity, permissions, and domain workflows through Supabase.

## Components

| Component | Responsibility | Boundary |
| --- | --- | --- |
| Supabase | PostgreSQL, Auth, RLS, RPC gateways, migrations, shared business rules | Owns persistent data and privileged operations |
| packages/contracts | Shared types, RPC names, enums, labels, and Minecraft command contracts | Defines names and shapes, not database access |
| bot | Telegram UX, onboarding, notifications, moderation/community workflows | Calls shared backend contracts; does not own domain truth |
| site | Public community experience and participant account surfaces | Uses authenticated server-side adapters and public-safe APIs |
| panel | Staff/admin experience | Uses server-side authorization and staff RPC/RBAC |
| minecraft-plugin | In-game commands, identity, whitelist, events, and Paper integration | Uses server-side RPC; no direct table CRUD |
| packages/ui | Shared visual components | Presentation only |
| modules/registry.json | Domain ownership, dependencies, consumers, contracts, and removal metadata | Architecture registry, not a runtime feature toggle |

## Data flow

```text
Telegram users ──> bot ───────────────┐
Players ─────────> participant site ──┤
Staff ───────────> admin panel ───────┼──> Supabase Auth / RPC / RLS / PostgreSQL
Minecraft ──────> Paper plugin ───────┘
```

The preferred dependency direction is:

```text
handler / route / command → adapter → shared contract → Supabase RPC/domain
```

Avoid direct UI-to-table access or duplicated business rules in multiple consumers.

## Security boundaries

- Browser code may use only public/publishable Supabase credentials.
- Supabase service-role credentials are server-only and must never be bundled into client code.
- Privileged actions require backend-side authorization and appropriate RLS/RPC grants.
- Minecraft plugin config is runtime-only; never commit the real config.yml.
- Telegram and Redis credentials belong in the bot hosting environment.
- Hiding a button or command is not an authorization check.

## Module lifecycle

The machine-readable registry is modules/registry.json. It records ownership and dependencies. Runtime enablement is managed separately through the central module-state control plane stored in Supabase.

A registry status such as active or deprecated does not by itself enable or disable production behavior. Consumers must use the central module-state contract where runtime management is required.

## Database changes

Production schema changes are forward-migration only: add a migration, backfill or reconcile data when required, switch consumers to the new contract, and remove obsolete structures in a later forward migration.

Do not edit historical migrations that may already have run on a deployed database. Do not apply migrations to production without confirming its project reference, migration history, and backup.

## Further reading

- [Development workflow](DEVELOPMENT.md)
- [Operations](OPERATIONS.md)
- [Configuration](CONFIGURATION.md)
