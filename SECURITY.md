# Security Policy

## Scope

PRISMA is a self-hosted platform composed of a Telegram bot, participant website, staff dashboard, Paper plugin, and Supabase backend.

## Reporting a vulnerability

Do not publish exploitable vulnerabilities, credentials, personal data, or production access details in public issues. Use GitHub private vulnerability reporting for this repository when available. Otherwise contact the maintainers privately through a channel listed on the maintainer's GitHub profile. Include the affected component, impact, reproduction conditions, and a suggested mitigation when possible.

Never include real tokens, service-role keys, database dumps, or player records in a report.

## Secret handling

- Never commit .env files, runtime Minecraft config.yml, Telegram tokens, Redis credentials, Supabase service-role keys, private keys, or production exports.
- Keep SUPABASE_SERVICE_ROLE_KEY on trusted server runtimes only. Never expose it through a NEXT_PUBLIC_ variable or browser bundle.
- Store deployment secrets in the hosting provider's secret manager.
- Rotate any credential that may have appeared in Git history, logs, screenshots, or public messages.
- Use least-privilege permissions and review Supabase RLS, RPC grants, and staff RBAC changes.

Security guidance applies to the PRISMA 2.1.0 integration candidate. Source-level controls do not replace testing the deployed configuration and database policies.
