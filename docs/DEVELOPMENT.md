# Development Workflow

## Implementation order

Do not begin a cross-component feature with UI alone. Define the domain contract first, then implement the database/backend boundary and consumers.

Recommended sequence:
1. Define the domain decision and ownership.
2. Add shared types, enums, and RPC names to packages/contracts.
3. Add a forward Supabase migration with RLS and explicit RPC grants.
4. Implement server-side adapters.
5. Connect bot, site, panel, and/or plugin consumers.
6. Add UI and user-facing error handling.
7. Add architecture and release verification.
8. Update docs and release notes.

## Module registry

The module registry is modules/registry.json. It records ownership, dependencies, consumers, contract namespaces, source roots, and removal metadata. It is not itself the runtime feature-flag system.

Create a module scaffold with:

```powershell
node scripts/create-feature-module.mjs --id=example --title="Example module" --owner=core
```

Complete the registry entry, contracts, migrations, adapters, verification, and removal plan. Generated module contracts must be regenerated through the repository script rather than edited manually.

## Database rules

- Production changes use new forward migrations.
- Do not edit historical migrations after deployment.
- Do not add privileged SQL without explicit grants and security review.
- Avoid direct table CRUD from consumers when a canonical RPC contract exists.
- Prefer add → backfill → switch consumers → remove old structures in a later migration.

## Error handling

Users should receive business-safe messages. Technical details belong in sanitized server logs and authorized diagnostics, not raw client responses.

## Review checklist

- Shared domain contracts are defined in one place.
- Server-side authorization and RLS/RBAC have been reviewed.
- No service-role key or secret is exposed to browser code.
- Consumers do not duplicate domain rules.
- Migrations are forward-only and safe for the intended target.
- Tests/checks are recorded, including runtime tests that remain unverified.
- Documentation and rollback notes are updated.
