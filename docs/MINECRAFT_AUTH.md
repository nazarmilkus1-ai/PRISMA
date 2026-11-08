# Minecraft Authentication

## Java Edition

Java players must pass PRISMA whitelist and identity checks. Password authentication is implemented by PrismaPlugin; SimpleLogin is not required by this implementation.

On join, a Java player remains unauthenticated until PRISMA Auth accepts /login. A player without a configured password can use /register, or set the password from the participant site's Minecraft settings.

PRISMA Auth stores a bcrypt password hash in the private minecraft_auth_credentials table. The Paper plugin does not receive the hash; it calls server-only Supabase RPC gateways over HTTPS for status, registration, login, and password changes.

Five failed login attempts create a temporary 10-minute lock. Password commands are excluded from Minecraft analytics so credentials are not written to the command event log.

## Bedrock Edition

Bedrock players are detected through Floodgate. They do not use PRISMA Auth and do not receive password prompts.

The plugin expects the canonical PRISMA account platform to be BEDROCK and binds the observed Minecraft UUID to the approved PRISMA user on first successful whitelist validation. A later UUID or platform mismatch is rejected.

If Floodgate is missing or cannot be queried, Bedrock detection fails closed: the player is treated as Java and must satisfy the PRISMA Auth path.

## Shared contract

The participant site can set or change the Java password through authenticated PRISMA RPCs. The Telegram bot exposes auth status but does not accept passwords. The staff panel exposes status only and never receives password hashes.

The canonical command/auth catalog is packages/contracts/minecraft-commands.json and is consumed by the site, bot, and plugin.

## Operations

A production Java server must keep PrismaPlugin connected to the intended PRISMA Supabase project. Bedrock support requires Geyser/Floodgate to be installed and initialized before players join. Validate both flows on an isolated Paper test server before production.
