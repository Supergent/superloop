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

function isExternalUrl(src) {
  return (
    src.startsWith("http://") ||
    src.startsWith("https://") ||
    src.startsWith("//") ||
    src.startsWith("data:") ||
    src.startsWith("blob:")
  );
}

function extractScriptSrcs(html) {
  const scripts = [];
  const regex = /<script\b[^>]*\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>/gi;
  let match;
  while ((match = regex.exec(html)) !== null) {
    scripts.push(match[1] || match[2] || match[3]);
  }
  return scripts;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function selectorPresent(html, selector) {
  if (!selector) return true;
  if (selector.startsWith("#")) {
    const id = escapeRegExp(selector.slice(1));
    const idRegex = new RegExp(`id\\s*=\\s*["']${id}["']`, "i");
    return idRegex.test(html);
  }
  if (selector.startsWith(".")) {
    const cls = escapeRegExp(selector.slice(1));
    const classRegex = new RegExp(`class\\s*=\\s*["'][^"']*\\b${cls}\\b[^"']*["']`, "i");
    return classRegex.test(html);
  }
  return html.includes(selector);
}

function normalizeEntry(entry, repo) {
  if (!entry) return null;
  if (path.isAbsolute(entry)) {
    return entry;
  }
  return path.resolve(repo, entry);
}

function resolveScriptPath(src, htmlDir, webRoot) {
  if (src.startsWith("/")) {
    return path.resolve(webRoot, src.slice(1));
  }
  return path.resolve(htmlDir, src);
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

  if (!config || !config.entry) {
    console.log(
      JSON.stringify({
        ok: false,
        error: "missing_entry",
        message: "validation preflight requires entry path",
      })
    );
    process.exit(1);
  }

  const entryPath = normalizeEntry(config.entry, args.repo);
  const result = {
    ok: true,
    entry: {
      path: entryPath,
      exists: false,
      bytes: 0,
    },
    scripts: [],
    checks: [],
    errors: [],
  };

  if (!entryPath || !fs.existsSync(entryPath)) {
    result.ok = false;
    result.errors.push(`entry_not_found:${config.entry}`);
    console.log(JSON.stringify(result));
    process.exit(1);
  }

  const entryStat = fs.statSync(entryPath);
  result.entry.exists = true;
  result.entry.bytes = entryStat.size;
  result.checks.push("entry_exists");

  const html = fs.readFileSync(entryPath, "utf8");
  if (!html.trim()) {
    result.ok = false;
    result.errors.push("entry_empty");
  }

  const requiredSelectors = Array.isArray(config.required_selectors)
    ? config.required_selectors
    : [];
  for (const selector of requiredSelectors) {
    if (!selectorPresent(html, selector)) {
      result.ok = false;
      result.errors.push(`missing_selector:${selector}`);
    }
  }

  const requiredText = Array.isArray(config.required_text) ? config.required_text : [];
  for (const text of requiredText) {
    if (!html.includes(text)) {
      result.ok = false;
      result.errors.push(`missing_text:${text}`);
    }
  }

  const scriptSrcs = extractScriptSrcs(html);
  const webRoot = config.web_root
    ? path.resolve(args.repo, config.web_root)
    : path.dirname(entryPath);
  const htmlDir = path.dirname(entryPath);

  if (config.require_scripts !== false && scriptSrcs.length === 0) {
    result.ok = false;
    result.errors.push("no_script_tags");
  }

  const minScriptBytes = Number.isFinite(config.min_script_bytes)
    ? config.min_script_bytes
    : 1;
  const maxScriptKb = Number.isFinite(config.max_script_kb) ? config.max_script_kb : null;

  for (const src of scriptSrcs) {
    if (!src) continue;
    if (isExternalUrl(src)) {
      result.scripts.push({ src, external: true, ok: true });
      continue;
    }

    const resolved = resolveScriptPath(src, htmlDir, webRoot);
    const scriptResult = {
      src,
      path: resolved,
      exists: false,
      bytes: 0,
      ok: true,
    };

    if (!fs.existsSync(resolved)) {
      scriptResult.ok = false;
      result.ok = false;
      result.errors.push(`script_missing:${src}`);
      result.scripts.push(scriptResult);
      continue;
    }

    const stat = fs.statSync(resolved);
    scriptResult.exists = true;
    scriptResult.bytes = stat.size;
    if (stat.size < minScriptBytes) {
      scriptResult.ok = false;
      result.ok = false;
      result.errors.push(`script_too_small:${src}`);
    }
    if (maxScriptKb !== null && stat.size > maxScriptKb * 1024) {
      scriptResult.ok = false;
      result.ok = false;
      result.errors.push(`script_too_large:${src}`);
    }

    result.scripts.push(scriptResult);
  }

  if (result.ok) {
    result.checks.push("preflight_ok");
  }

  console.log(JSON.stringify(result));
  process.exit(result.ok ? 0 : 1);
}

main();
