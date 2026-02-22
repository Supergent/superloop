#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = { repo: process.cwd(), config: null };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--repo" && argv[i + 1]) {
      args.repo = argv[i + 1];
      i += 1;
      continue;
    }
    if (arg === "--config" && argv[i + 1]) {
      args.config = argv[i + 1];
      i += 1;
      continue;
    }
  }
  return args;
}

function loadConfig(raw) {
  if (!raw) return null;
  if (raw.trim().startsWith("{")) {
    return JSON.parse(raw);
  }
  if (fs.existsSync(raw)) {
    return JSON.parse(fs.readFileSync(raw, "utf8"));
  }
  return JSON.parse(raw);
}

function resolveRepoPath(repo, filePath) {
  if (!filePath || typeof filePath !== "string") return null;
  if (path.isAbsolute(filePath)) return filePath;
  return path.resolve(repo, filePath);
}

function loadFileOrError(repo, filePath) {
  const resolved = resolveRepoPath(repo, filePath);
  if (!resolved) {
    return { ok: false, reason: "missing_path", resolved: null };
  }
  if (!fs.existsSync(resolved)) {
    return { ok: false, reason: "file_not_found", resolved };
  }
  if (!fs.statSync(resolved).isFile()) {
    return { ok: false, reason: "not_a_file", resolved };
  }
  return { ok: true, resolved, content: fs.readFileSync(resolved, "utf8") };
}

function compileRegex(pattern, flags = "") {
  try {
    return { ok: true, regex: new RegExp(pattern, flags) };
  } catch (error) {
    return { ok: false, error: `invalid_regex:${error.message}` };
  }
}

function runMarkdownChecklistComplete(check, repo) {
  const file = loadFileOrError(repo, check.path);
  if (!file.ok) {
    return { ok: false, reason: file.reason, details: { path: check.path } };
  }

  const unchecked = [];
  const lines = file.content.split(/\r?\n/);
  let inCodeFence = false;

  for (let idx = 0; idx < lines.length; idx += 1) {
    const line = lines[idx];
    if (/^\s*```/.test(line)) {
      inCodeFence = !inCodeFence;
      continue;
    }
    if (inCodeFence) continue;
    if (/\[[ ]\]/.test(line)) {
      unchecked.push({ line: idx + 1, text: line.trim() });
    }
  }

  if (unchecked.length > 0) {
    return {
      ok: false,
      reason: "unchecked_items_remaining",
      details: { count: unchecked.length, first: unchecked.slice(0, 10) },
    };
  }

  return { ok: true };
}

function runFileRegexPresent(check, repo) {
  const file = loadFileOrError(repo, check.path);
  if (!file.ok) {
    return { ok: false, reason: file.reason, details: { path: check.path } };
  }
  const compiled = compileRegex(check.pattern || "", check.flags || "");
  if (!compiled.ok) {
    return { ok: false, reason: compiled.error };
  }
  if (!compiled.regex.test(file.content)) {
    return { ok: false, reason: "pattern_not_found", details: { pattern: check.pattern } };
  }
  return { ok: true };
}

function runFileRegexAbsent(check, repo) {
  const file = loadFileOrError(repo, check.path);
  if (!file.ok) {
    return { ok: false, reason: file.reason, details: { path: check.path } };
  }
  const compiled = compileRegex(check.pattern || "", check.flags || "");
  if (!compiled.ok) {
    return { ok: false, reason: compiled.error };
  }
  if (compiled.regex.test(file.content)) {
    return { ok: false, reason: "pattern_present", details: { pattern: check.pattern } };
  }
  return { ok: true };
}

function runFileContainsAll(check, repo) {
  const file = loadFileOrError(repo, check.path);
  if (!file.ok) {
    return { ok: false, reason: file.reason, details: { path: check.path } };
  }
  const needles = Array.isArray(check.needles) ? check.needles : [];
  const missing = needles.filter((needle) => typeof needle === "string" && !file.content.includes(needle));
  if (missing.length > 0) {
    return { ok: false, reason: "missing_required_content", details: { missing } };
  }
  return { ok: true };
}

function runFileNotContainsAny(check, repo) {
  const file = loadFileOrError(repo, check.path);
  if (!file.ok) {
    return { ok: false, reason: file.reason, details: { path: check.path } };
  }
  const needles = Array.isArray(check.needles) ? check.needles : [];
  const present = needles.filter((needle) => typeof needle === "string" && file.content.includes(needle));
  if (present.length > 0) {
    return { ok: false, reason: "forbidden_content_present", details: { present } };
  }
  return { ok: true };
}

function runFileExists(check, repo) {
  const resolved = resolveRepoPath(repo, check.path);
  if (!resolved || !fs.existsSync(resolved)) {
    return { ok: false, reason: "file_not_found", details: { path: check.path } };
  }
  return { ok: true };
}

function runFileNonempty(check, repo) {
  const file = loadFileOrError(repo, check.path);
  if (!file.ok) {
    return { ok: false, reason: file.reason, details: { path: check.path } };
  }
  const minChars = Number.isFinite(check.min_chars) ? Math.max(0, check.min_chars) : 1;
  const size = file.content.trim().length;
  if (size < minChars) {
    return { ok: false, reason: "file_too_short", details: { size, min_chars: minChars } };
  }
  return { ok: true };
}

function runCheck(check, repo) {
  if (!check || typeof check !== "object") {
    return { ok: false, reason: "invalid_check" };
  }

  switch (check.type) {
    case "markdown_checklist_complete":
      return runMarkdownChecklistComplete(check, repo);
    case "file_regex_present":
      return runFileRegexPresent(check, repo);
    case "file_regex_absent":
      return runFileRegexAbsent(check, repo);
    case "file_contains_all":
      return runFileContainsAll(check, repo);
    case "file_not_contains_any":
      return runFileNotContainsAny(check, repo);
    case "file_exists":
      return runFileExists(check, repo);
    case "file_nonempty":
      return runFileNonempty(check, repo);
    default:
      return { ok: false, reason: `unsupported_check_type:${check.type || "unknown"}` };
  }
}

function main() {
  const args = parseArgs(process.argv);

  let config;
  try {
    config = loadConfig(args.config);
  } catch (error) {
    console.log(
      JSON.stringify({
        ok: false,
        error: "invalid_config",
        message: error.message,
      })
    );
    process.exit(1);
  }

  const checks = Array.isArray(config?.checks) ? config.checks : [];
  const verified = [];
  const failed = [];

  for (let i = 0; i < checks.length; i += 1) {
    const check = checks[i] || {};
    const id =
      (typeof check.id === "string" && check.id.length > 0 && check.id) ||
      `${check.type || "unknown"}:${check.path || i}`;

    let result;
    try {
      result = runCheck(check, args.repo);
    } catch (error) {
      result = { ok: false, reason: `check_runtime_error:${error.message}` };
    }

    if (result.ok) {
      verified.push(id);
    } else {
      failed.push({
        id,
        type: check.type || "unknown",
        path: check.path || null,
        reason: result.reason || "unknown_error",
        details: result.details || null,
      });
    }
  }

  const output = {
    ok: failed.length === 0,
    generated_at: new Date().toISOString(),
    total: checks.length,
    passed: verified.length,
    verified,
    failed,
  };

  console.log(JSON.stringify(output));
  process.exit(output.ok ? 0 : 1);
}

main();
