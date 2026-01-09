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
  if (!filePath) return null;
  if (path.isAbsolute(filePath)) {
    return filePath;
  }
  return path.resolve(repo, filePath);
}

function resolveEntryFromConfig(config, repo) {
  if (config.entry) {
    return resolveRepoPath(repo, config.entry);
  }
  if (config.url && typeof config.url === "string" && config.url.startsWith("file://")) {
    const raw = config.url.replace("file://", "");
    const expanded = raw.replace("{repo}", repo);
    return resolveRepoPath(repo, expanded);
  }
  return null;
}

function runWebElementCheck(mapping, repo) {
  const entryPath = resolveEntryFromConfig(mapping.config || {}, repo);
  if (!entryPath || !fs.existsSync(entryPath)) {
    return { ok: false, errors: [`entry_not_found:${mapping.config?.entry || ""}`] };
  }

  const html = fs.readFileSync(entryPath, "utf8");
  const selectors = Array.isArray(mapping.config?.selectors) ? mapping.config.selectors : [];
  const missing = selectors.filter((selector) => !html.includes(selector));
  if (missing.length > 0) {
    return { ok: false, errors: missing.map((selector) => `missing_selector:${selector}`) };
  }
  return { ok: true, errors: [] };
}

function runWebTextCheck(mapping, repo) {
  const entryPath = resolveEntryFromConfig(mapping.config || {}, repo);
  if (!entryPath || !fs.existsSync(entryPath)) {
    return { ok: false, errors: [`entry_not_found:${mapping.config?.entry || ""}`] };
  }

  const html = fs.readFileSync(entryPath, "utf8");
  const texts = Array.isArray(mapping.config?.texts) ? mapping.config.texts : [];
  const missing = texts.filter((text) => !html.includes(text));
  if (missing.length > 0) {
    return { ok: false, errors: missing.map((text) => `missing_text:${text}`) };
  }
  return { ok: true, errors: [] };
}

function runFileExistsCheck(mapping, repo) {
  const paths = Array.isArray(mapping.config?.paths) ? mapping.config.paths : [];
  const missing = paths.filter((p) => !fs.existsSync(resolveRepoPath(repo, p)));
  if (missing.length > 0) {
    return { ok: false, errors: missing.map((p) => `file_missing:${p}`) };
  }
  return { ok: true, errors: [] };
}

function runMapping(mapping, repo) {
  if (!mapping || typeof mapping !== "object") {
    return { ok: false, errors: ["invalid_mapping"] };
  }
  const type = mapping.test_type || mapping.type;
  if (type === "web_element") {
    return runWebElementCheck(mapping, repo);
  }
  if (type === "web_text") {
    return runWebTextCheck(mapping, repo);
  }
  if (type === "file_exists") {
    return runFileExistsCheck(mapping, repo);
  }
  return { ok: false, errors: [`unsupported_test_type:${type}`] };
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

  const mappingFile = config?.mapping_file;
  if (!mappingFile) {
    console.log(
      JSON.stringify({
        ok: false,
        error: "missing_mapping_file",
      })
    );
    process.exit(1);
  }

  const mappingPath = resolveRepoPath(args.repo, mappingFile);
  if (!mappingPath || !fs.existsSync(mappingPath)) {
    console.log(
      JSON.stringify({
        ok: false,
        error: "mapping_file_not_found",
        path: mappingFile,
      })
    );
    process.exit(1);
  }

  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(mappingPath, "utf8"));
  } catch (error) {
    console.log(
      JSON.stringify({
        ok: false,
        error: "invalid_mapping_json",
        message: error.message,
      })
    );
    process.exit(1);
  }

  const mappings = Array.isArray(payload.mappings) ? payload.mappings : [];
  const verified = [];
  const failed = [];

  for (const mapping of mappings) {
    const result = runMapping(mapping, args.repo);
    if (result.ok) {
      verified.push(mapping.checklist_item || "unnamed");
    } else {
      failed.push({
        checklist_item: mapping.checklist_item || "unnamed",
        errors: result.errors,
      });
    }
  }

  const ok = failed.length === 0;
  const output = {
    ok,
    generated_at: new Date().toISOString(),
    verified,
    failed,
  };
  console.log(JSON.stringify(output));
  process.exit(ok ? 0 : 1);
}

main();
