#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const SESSION_SCRIPT = path.join(__dirname, "handover-session-start.js");
const COMMAND = `node ${shellQuote(SESSION_SCRIPT)}`;
const CLAUDE_SETTINGS_PATH = path.join(process.cwd(), ".claude", "settings.json");
const CODEX_HOOKS_PATH = path.join(process.cwd(), ".codex", "hooks.json");
const HANDOVER_SCRIPT_PATTERN = /handover-session-start\.js(?:'|")?$/;

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) return {};
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function hookMatches(hook) {
  return hook.type === "command" && (hook.command === COMMAND || HANDOVER_SCRIPT_PATTERN.test(hook.command || ""));
}

function normalizeHook(entry, { includeStatusMessage }) {
  let changed = false;
  for (const hook of entry.hooks || []) {
    if (!hookMatches(hook)) continue;
    if (hook.command !== COMMAND) {
      hook.command = COMMAND;
      changed = true;
    }
    if (hook.timeout == null) {
      hook.timeout = 5;
      changed = true;
    }
    if (includeStatusMessage && !hook.statusMessage) {
      hook.statusMessage = "Injecting handover context";
      changed = true;
    }
  }
  return changed;
}

function ensureSessionStartHook(config, { includeStatusMessage }) {
  config.hooks ||= {};
  config.hooks.SessionStart ||= [];

  for (const entry of config.hooks.SessionStart) {
    if (Array.isArray(entry.hooks) && entry.hooks.some(hookMatches)) {
      return { config, changed: normalizeHook(entry, { includeStatusMessage }) };
    }
  }

  const hook = {
    type: "command",
    command: COMMAND,
    timeout: 5,
  };
  if (includeStatusMessage) {
    hook.statusMessage = "Injecting handover context";
  }

  config.hooks.SessionStart.push({
    matcher: "startup|resume|clear|compact",
    hooks: [hook],
  });

  return { config, changed: true };
}

function installClaudeHook() {
  const settings = readJson(CLAUDE_SETTINGS_PATH);
  const result = ensureSessionStartHook(settings, { includeStatusMessage: false });
  if (result.changed) {
    writeJson(CLAUDE_SETTINGS_PATH, result.config);
    return `Installed handover SessionStart hook in ${CLAUDE_SETTINGS_PATH}.`;
  }
  return "handover Claude Code SessionStart hook already installed.";
}

function installCodexHook() {
  const hooksConfig = readJson(CODEX_HOOKS_PATH);
  hooksConfig.$comment ||= "Codex hooks for project-local agent workflows.";
  const result = ensureSessionStartHook(hooksConfig, { includeStatusMessage: true });
  if (result.changed) {
    writeJson(CODEX_HOOKS_PATH, result.config);
    return `Installed handover SessionStart hook in ${CODEX_HOOKS_PATH}.`;
  }
  return "handover Codex SessionStart hook already installed.";
}

function main() {
  const targets = new Set(process.argv.slice(2));
  const installClaude = targets.size === 0 || targets.has("--claude") || targets.has("--all");
  const installCodex = targets.size === 0 || targets.has("--codex") || targets.has("--all");

  const messages = [];
  if (installClaude) messages.push(installClaudeHook());
  if (installCodex) messages.push(installCodexHook());
  if (messages.length === 0) {
    console.error("Usage: install-handover-hooks.js [--claude] [--codex] [--all]");
    process.exit(1);
  }

  console.log(messages.join("\n"));
}

main();
