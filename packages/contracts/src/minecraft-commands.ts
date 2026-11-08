import catalog from "../minecraft-commands.json";

export const MINECRAFT_COMMAND_CATALOG = catalog;
export const MINECRAFT_COMMANDS = catalog.commands;
export const MINECRAFT_ROLES = catalog.roles;
export const MINECRAFT_AUTHENTICATION = catalog.authentication;
export const MINECRAFT_CLAN_WAR_SUBCOMMANDS = catalog.clan_war_subcommands;

export type MinecraftCommand = (typeof catalog.commands)[number];
export type MinecraftRole = (typeof catalog.roles)[number];
export type MinecraftAuthentication = (typeof catalog.authentication)[number];
