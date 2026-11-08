# Feature Module Template

Copy this document when proposing a major PRISMA domain module.

## Identity

- Module ID:
- Title:
- Owner:
- Status: planned / active / deprecated
- Dependencies:

## Purpose

Describe the user problem and the domain responsibility.

## Contract

- Shared types and enums:
- RPC names:
- Database tables/views:
- Permissions and RLS:
- Audit requirements:

## Consumers

- [ ] Telegram bot
- [ ] Participant website
- [ ] Staff dashboard
- [ ] Minecraft plugin
- [ ] Notifications
- [ ] Public API

List the exact adapters, routes, handlers, commands, or pages for each consumer.

## Dependencies and ownership

List modules this feature uses and namespaces it owns. Do not claim ownership of another module's contract namespace.

## Verification

- [ ] Module registry updated
- [ ] Shared contract updated
- [ ] Forward migration added
- [ ] RLS/RPC grants reviewed
- [ ] Consumer tests/build checks pass
- [ ] Runtime smoke test completed
- [ ] Security review completed

## Rollout and removal

Describe how the module is enabled/disabled, how it can be rolled back, and the order for removing entrypoints, adapters, contracts, database structures, and permissions.
