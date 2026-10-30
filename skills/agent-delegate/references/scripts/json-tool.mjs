// JSON reader, checker and builder for agent-delegate. Callers pass jq-like
// flags and one JavaScript expression; the input arrives on stdin and results
// go to stdout. Paths never reach this process, so MSYS argument conversion
// and MSYS FIFOs stay on the bash side.
//
// Expression scope: d (input value), $ (--arg / --argjson values), EMPTY,
// each(), alt(), eq(), type(), len(), num().
//
// Exit codes follow jq: 2 for unreadable input or arguments, 5 when the
// expression throws, and with -e: 1 when the last output is false or null,
// 4 when nothing was output.

import { readFileSync } from "node:fs";

const EMPTY = Symbol("empty");

class Stream {
  constructor(values) {
    this.values = values;
  }
}

function type(v) {
  if (v === null || v === undefined) return "null";
  if (Array.isArray(v)) return "array";
  if (typeof v === "boolean" || typeof v === "number" || typeof v === "string") return typeof v;
  return "object";
}

function each(v) {
  if (Array.isArray(v)) return new Stream(v);
  if (type(v) === "object") return new Stream(Object.values(v));
  throw new Error(`Cannot iterate over ${type(v)}`);
}

function alt(a, b) {
  return a === null || a === undefined || a === false ? b : a;
}

function eq(a, b) {
  const ta = type(a);
  if (ta !== type(b)) return false;
  if (ta === "null") return true;
  if (ta === "array") return a.length === b.length && a.every((x, i) => eq(x, b[i]));
  if (ta === "object") {
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => Object.hasOwn(b, k) && eq(a[k], b[k]));
  }
  return a === b;
}

function len(v) {
  switch (type(v)) {
    case "null":
      return 0;
    case "string":
      return [...v].length;
    case "array":
      return v.length;
    case "object":
      return Object.keys(v).length;
    case "number":
      return Math.abs(v);
    default:
      throw new Error(`${type(v)} has no length`);
  }
}

// jq writes a missing field as null; JSON.stringify would drop the key.
function keepNull(_key, v) {
  return v === undefined ? null : v;
}

// jq tonumber: a numeric string becomes a number; anything else is an error.
function num(v) {
  if (typeof v === "number") return v;
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) return Number(v);
  throw new Error(`Cannot parse ${JSON.stringify(v)} as a number`);
}

// Failures unwind to main() instead of calling process.exit(), so stdout that
// was already written still drains into a pipe before the process ends.
class Exit extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function fail(code, message) {
  throw new Exit(code, message);
}

function main() {
  if (Number(process.versions.node.split(".")[0]) < 18) fail(2, "node 18 or later is required");
  const opts = { e: false, r: false, c: false, n: false, s: false, R: false };
  const args = {};
  let expr = null;
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--arg" || a === "--argjson") {
      if (i + 2 >= argv.length) fail(2, `${a} needs a name and a value`);
      const name = argv[i + 1];
      const value = argv[i + 2];
      if (a === "--arg") {
        args[name] = value;
      } else {
        try {
          args[name] = JSON.parse(value);
        } catch {
          fail(2, `--argjson ${name}: invalid JSON`);
        }
      }
      i += 2;
    } else if (/^-[ercnsR]+$/.test(a)) {
      for (const f of a.slice(1)) opts[f] = true;
    } else if (expr === null) {
      expr = a;
    } else {
      fail(2, `unexpected argument: ${a}`);
    }
  }
  if (expr === null) fail(2, "missing expression");

  let evaluate;
  try {
    evaluate = new Function(
      "d",
      "$",
      "EMPTY",
      "each",
      "alt",
      "eq",
      "type",
      "len",
      "num",
      `"use strict"; return (${expr});`,
    );
  } catch (error) {
    fail(2, `invalid expression: ${error.message}`);
  }

  function inputs() {
    if (opts.n) return { values: [null], error: null };
    const text = readFileSync(0, "utf8");
    if (opts.R) {
      if (opts.s) return { values: [text], error: null };
      const lines = text.split("\n");
      if (lines[lines.length - 1] === "") lines.pop();
      return { values: lines, error: null };
    }
    let values = [];
    let error = null;
    if (text.trim() !== "") {
      try {
        values = [JSON.parse(text)];
      } catch {
        for (const line of text.split("\n")) {
          if (line.trim() === "") continue;
          try {
            values.push(JSON.parse(line));
          } catch {
            error = "input is not valid JSON";
            break;
          }
        }
      }
    }
    if (opts.s) values = [values];
    return { values, error };
  }

  const out = [];
  let last;
  let produced = false;

  function emit(v) {
    if (v === EMPTY) return;
    if (v instanceof Stream) {
      for (const x of v.values) emit(x);
      return;
    }
    const value = v === undefined ? null : v;
    produced = true;
    last = value;
    if (opts.r && typeof value === "string") out.push(`${value}\n`);
    else out.push(`${JSON.stringify(value, keepNull, opts.c ? undefined : 2)}\n`);
  }

  // Reading an argument that was not passed is an error, as in jq.
  const named = new Proxy(args, {
    get(target, key) {
      if (typeof key === "string" && !Object.hasOwn(target, key)) throw new Error(`$${key} is not defined`);
      return target[key];
    },
  });

  const { values, error } = inputs();
  let code = 0;
  try {
    for (const value of values) emit(evaluate(value, named, EMPTY, each, alt, eq, type, len, num));
  } catch (e) {
    process.stdout.write(out.join(""));
    fail(5, e.message);
  }
  process.stdout.write(out.join(""));
  if (error !== null) fail(2, error);
  if (opts.e) {
    if (!produced) code = 4;
    else if (last === null || last === false) code = 1;
  }
  return code;
}

try {
  process.exitCode = main();
} catch (error) {
  if (!(error instanceof Exit)) throw error;
  process.stderr.write(`json-tool: ${error.message}\n`);
  process.exitCode = error.code;
}
