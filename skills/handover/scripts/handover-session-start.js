#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

function readHookInput() {
  try {
    const raw = fs.readFileSync(0, "utf8").trim();
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function findHandover(cwd) {
  const candidates = [
    path.join(cwd, "handover.md"),
    path.join(cwd, ".handover", "current.md"),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate));
}

function section(markdown, name) {
  const lines = markdown.split(/\r?\n/);
  const start = lines.findIndex((line) => line.trim() === `## ${name}`);
  if (start === -1) return "";

  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith("## ")) break;
    body.push(line);
  }
  return body.join("\n").trim();
}

function firstLines(text, maxLines = 3) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, maxLines)
    .join("\n");
}

function buildContext(handoverPath, markdown) {
  const goal = firstLines(section(markdown, "Goal"), 2) || "(not specified)";
  const nextAction = firstLines(section(markdown, "Next Action"), 3) || "(not specified)";
  const stopConditions = firstLines(section(markdown, "Stop Conditions"), 3) || "(not specified)";
  const relativePath = path.relative(process.cwd(), handoverPath) || handoverPath;

  return [
    `A local handover exists at ./${relativePath}.`,
    "Before editing, read it and verify it against the current git state.",
    "Summary:",
    `- Goal: ${goal}`,
    `- Next Action: ${nextAction}`,
    `- Stop Conditions: ${stopConditions}`,
  ].join("\n");
}

function main() {
  const input = readHookInput();
  const cwd = input.cwd || process.cwd();
  const handoverPath = findHandover(cwd);
  if (!handoverPath) return;

  const markdown = fs.readFileSync(handoverPath, "utf8");
  const previousCwd = process.cwd();
  process.chdir(cwd);
  const additionalContext = buildContext(handoverPath, markdown);
  process.chdir(previousCwd);

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext,
      },
    })
  );
}

main();
