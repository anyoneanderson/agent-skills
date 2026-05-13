#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const SETTINGS_PATH = path.join(process.cwd(), ".claude", "settings.json");
const COMMAND = "node skills/handover/scripts/handover-session-start.js";

function readJson(filePath) {
  if (!fs.existsSync(filePath)) return {};
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function ensureSessionStartHook(settings) {
  settings.hooks ||= {};
  settings.hooks.SessionStart ||= [];

  const existing = settings.hooks.SessionStart.some((entry) =>
    Array.isArray(entry.hooks) &&
    entry.hooks.some((hook) => hook.type === "command" && hook.command === COMMAND)
  );

  if (existing) return { settings, changed: false };

  settings.hooks.SessionStart.push({
    matcher: "startup|resume|clear|compact",
    hooks: [
      {
        type: "command",
        command: COMMAND,
      },
    ],
  });

  return { settings, changed: true };
}

function main() {
  fs.mkdirSync(path.dirname(SETTINGS_PATH), { recursive: true });
  const settings = readJson(SETTINGS_PATH);
  const result = ensureSessionStartHook(settings);

  if (!result.changed) {
    console.log("handover SessionStart hook already installed.");
    return;
  }

  fs.writeFileSync(SETTINGS_PATH, `${JSON.stringify(result.settings, null, 2)}\n`);
  console.log(`Installed handover SessionStart hook in ${SETTINGS_PATH}.`);
}

main();
