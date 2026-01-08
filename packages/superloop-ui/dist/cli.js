#!/usr/bin/env node

// src/cli.ts
import { Command } from "commander";

// src/dev-server.ts
import { spawn } from "child_process";
import fs5 from "fs/promises";
import http from "http";
import path6 from "path";

// src/lib/fs-utils.ts
import fs from "fs/promises";
async function fileExists(path8) {
  try {
    await fs.access(path8);
    return true;
  } catch {
    return false;
  }
}
async function readJson(path8) {
  try {
    const raw = await fs.readFile(path8, "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// src/lib/package-root.ts
import path from "path";
import { fileURLToPath } from "url";
function resolvePackageRoot(metaUrl) {
  const filename = fileURLToPath(metaUrl);
  const dir = path.dirname(filename);
  return path.resolve(dir, "..");
}

// src/lib/paths.ts
import path2 from "path";
var SUPERLOOP_DIR = ".superloop";
var UI_PROTOTYPES_DIR = path2.join(SUPERLOOP_DIR, "ui", "prototypes");
var LOOPS_DIR = path2.join(SUPERLOOP_DIR, "loops");
function resolveRepoRoot(repoRoot) {
  return repoRoot ? path2.resolve(repoRoot) : process.cwd();
}
function resolvePrototypesRoot(repoRoot) {
  return path2.join(repoRoot, UI_PROTOTYPES_DIR);
}
function resolveLoopsRoot(repoRoot) {
  return path2.join(repoRoot, LOOPS_DIR);
}
function resolveLoopDir(repoRoot, loopId) {
  return path2.join(resolveLoopsRoot(repoRoot), loopId);
}

// src/lib/bindings.ts
function injectBindings(template, data) {
  return template.replace(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g, (match, key) => {
    const value = resolvePath(data, key);
    if (value === void 0 || value === null) {
      return match;
    }
    if (typeof value === "object") {
      return JSON.stringify(value);
    }
    return String(value);
  });
}
function resolvePath(data, key) {
  if (!key.includes(".")) {
    return data[key];
  }
  return key.split(".").reduce((acc, segment) => {
    if (acc && typeof acc === "object" && segment in acc) {
      return acc[segment];
    }
    return void 0;
  }, data);
}

// src/lib/prototypes.ts
import fs2 from "fs/promises";
import path3 from "path";
var VERSION_EXTENSION = ".txt";
var META_FILENAME = "meta.json";
var TIMESTAMP_PATTERN = /^(\d{8}-\d{6})/;
function createTimestampId(date = /* @__PURE__ */ new Date()) {
  const pad = (value) => value.toString().padStart(2, "0");
  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  const hours = pad(date.getHours());
  const minutes = pad(date.getMinutes());
  const seconds = pad(date.getSeconds());
  return `${year}${month}${day}-${hours}${minutes}${seconds}`;
}
function formatTimestamp(date) {
  const pad = (value) => value.toString().padStart(2, "0");
  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  const hours = pad(date.getHours());
  const minutes = pad(date.getMinutes());
  const seconds = pad(date.getSeconds());
  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
}
async function listPrototypes(repoRoot) {
  const root = resolvePrototypesRoot(repoRoot);
  if (!await fileExists(root)) {
    return [];
  }
  const entries = await fs2.readdir(root, { withFileTypes: true });
  const viewsByName = /* @__PURE__ */ new Map();
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const view = await readViewDirectory(root, entry.name);
      if (view) {
        viewsByName.set(view.name, view);
      }
    }
  }
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(VERSION_EXTENSION)) {
      continue;
    }
    const viewName = path3.basename(entry.name, VERSION_EXTENSION);
    const filePath = path3.join(root, entry.name);
    const version = await readVersionFile(filePath, entry.name);
    const existing = viewsByName.get(viewName);
    if (existing) {
      if (!existing.versions.some((item) => item.filename === entry.name)) {
        existing.versions.push(version);
      }
      existing.versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
      existing.latest = existing.versions[existing.versions.length - 1];
    } else {
      viewsByName.set(viewName, {
        name: viewName,
        versions: [version],
        latest: version
      });
    }
  }
  return Array.from(viewsByName.values()).sort((a, b) => a.name.localeCompare(b.name));
}
async function createPrototypeVersion(params) {
  const root = resolvePrototypesRoot(params.repoRoot);
  const viewDir = path3.join(root, params.viewName);
  await fs2.mkdir(viewDir, { recursive: true });
  const timestampId = createTimestampId();
  const filename = `${timestampId}${VERSION_EXTENSION}`;
  const filePath = path3.join(viewDir, filename);
  await fs2.writeFile(filePath, params.content, "utf8");
  const metaPath = path3.join(viewDir, META_FILENAME);
  const meta = await readJson(metaPath) ?? {};
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const nextMeta = {
    description: params.description ?? meta.description,
    prompt: params.prompt ?? meta.prompt,
    createdAt: meta.createdAt ?? now,
    updatedAt: now
  };
  await fs2.writeFile(metaPath, JSON.stringify(nextMeta, null, 2), "utf8");
  return {
    id: timestampId,
    filename,
    path: filePath,
    createdAt: formatTimestamp(/* @__PURE__ */ new Date()),
    content: params.content
  };
}
async function readLatestPrototype(params) {
  const root = resolvePrototypesRoot(params.repoRoot);
  const viewDir = path3.join(root, params.viewName);
  const view = await fileExists(viewDir) ? await readViewDirectory(root, params.viewName) : null;
  const standaloneName = `${params.viewName}${VERSION_EXTENSION}`;
  const standalonePath = path3.join(root, standaloneName);
  if (await fileExists(standalonePath)) {
    const version = await readVersionFile(standalonePath, standaloneName);
    if (view) {
      if (!view.versions.some((item) => item.filename === standaloneName)) {
        view.versions.push(version);
      }
      view.versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
      view.latest = view.versions[view.versions.length - 1];
      return view;
    }
    return {
      name: params.viewName,
      versions: [version],
      latest: version
    };
  }
  return view ?? null;
}
async function readViewDirectory(root, viewName) {
  const viewDir = path3.join(root, viewName);
  const entries = await fs2.readdir(viewDir, { withFileTypes: true });
  const versions = [];
  let description;
  for (const entry of entries) {
    if (entry.isFile() && entry.name === META_FILENAME) {
      const meta = await readJson(path3.join(viewDir, entry.name));
      description = meta?.description;
      continue;
    }
    if (entry.isFile() && entry.name.endsWith(VERSION_EXTENSION)) {
      const filePath = path3.join(viewDir, entry.name);
      const version = await readVersionFile(filePath, entry.name);
      versions.push(version);
    }
  }
  if (versions.length === 0) {
    return null;
  }
  versions.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const latest = versions[versions.length - 1];
  return {
    name: viewName,
    description,
    versions,
    latest
  };
}
function readVersionId(filename, fallbackDate) {
  const match = filename.match(TIMESTAMP_PATTERN);
  if (match?.[1]) {
    return match[1];
  }
  return createTimestampId(fallbackDate);
}
async function readVersionFile(filePath, filename) {
  const stats = await fs2.stat(filePath);
  const content = await fs2.readFile(filePath, "utf8");
  const versionId = readVersionId(filename, stats.mtime);
  const createdAt = formatTimestamp(resolveTimestamp(versionId, stats.mtime));
  return {
    id: versionId,
    filename,
    path: filePath,
    createdAt,
    content
  };
}
function resolveTimestamp(versionId, fallbackDate) {
  const parsed = parseTimestampId(versionId);
  return parsed ?? fallbackDate;
}
function parseTimestampId(versionId) {
  const match = versionId.match(TIMESTAMP_PATTERN);
  if (!match?.[1]) {
    return null;
  }
  const id = match[1];
  const year = Number(id.slice(0, 4));
  const month = Number(id.slice(4, 6));
  const day = Number(id.slice(6, 8));
  const hours = Number(id.slice(9, 11));
  const minutes = Number(id.slice(11, 13));
  const seconds = Number(id.slice(13, 15));
  const date = new Date(year, month - 1, day, hours, minutes, seconds);
  if (Number.isNaN(date.getTime())) {
    return null;
  }
  return date;
}

// src/lib/superloop-data.ts
import fs3 from "fs/promises";
import path4 from "path";
async function resolveLoopId(repoRoot, preferred) {
  const loopsRoot = resolveLoopsRoot(repoRoot);
  if (!await fileExists(loopsRoot)) {
    return null;
  }
  if (preferred) {
    const loopDir = resolveLoopDir(repoRoot, preferred);
    if (await fileExists(loopDir)) {
      return preferred;
    }
  }
  if (process.env.SUPERLOOP_LOOP_ID) {
    const envId = process.env.SUPERLOOP_LOOP_ID;
    if (envId && await fileExists(resolveLoopDir(repoRoot, envId))) {
      return envId;
    }
  }
  const entries = await fs3.readdir(loopsRoot, { withFileTypes: true });
  const loopDirs = entries.filter((entry) => entry.isDirectory());
  if (loopDirs.length === 0) {
    return null;
  }
  const withStats = await Promise.all(
    loopDirs.map(async (entry) => {
      const dirPath = path4.join(loopsRoot, entry.name);
      const stats = await fs3.stat(dirPath);
      return { name: entry.name, mtimeMs: stats.mtimeMs };
    })
  );
  withStats.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return withStats[0]?.name ?? null;
}
async function loadSuperloopData(params) {
  const loopId = await resolveLoopId(params.repoRoot, params.loopId);
  if (!loopId) {
    return { data: {} };
  }
  const loopDir = resolveLoopDir(params.repoRoot, loopId);
  const runSummary = await readJson(path4.join(loopDir, "run-summary.json"));
  const testStatus = await readJson(path4.join(loopDir, "test-status.json"));
  const checklistStatus = await readJson(
    path4.join(loopDir, "checklist-status.json")
  );
  const eventFallback = await loadEventFallback(loopDir);
  const entry = runSummary?.entries?.[runSummary.entries.length - 1];
  const data = {
    loop_id: loopId,
    updated_at: runSummary?.updated_at ?? (/* @__PURE__ */ new Date()).toISOString()
  };
  if (entry?.iteration !== void 0) {
    data.iteration = String(entry.iteration);
  }
  if (entry?.promise?.text || entry?.promise?.expected) {
    data.promise = entry.promise.text ?? entry.promise.expected ?? "";
  }
  if (entry?.promise?.matched !== void 0) {
    data.promise_matched = entry.promise.matched ? "true" : "false";
  }
  if (entry?.gates?.tests) {
    data.test_status = entry.gates.tests;
  } else if (testStatus && typeof testStatus.ok === "boolean") {
    data.test_status = testStatus.ok ? testStatus.skipped ? "skipped" : "ok" : "failed";
  }
  if (entry?.gates?.checklist) {
    data.checklist_status = entry.gates.checklist;
  } else if (typeof checklistStatus?.ok === "boolean") {
    data.checklist_status = checklistStatus.ok ? "ok" : "failed";
  }
  if (entry?.gates?.evidence) {
    data.evidence_status = entry.gates.evidence;
  }
  if (entry?.gates?.approval) {
    data.approval_status = entry.gates.approval;
  }
  if (entry?.completion_ok !== void 0) {
    data.completion_ok = entry.completion_ok ? "true" : "false";
  }
  if (entry?.started_at) {
    data.started_at = entry.started_at;
  }
  if (entry?.ended_at) {
    data.ended_at = entry.ended_at;
  }
  applyEventFallback(data, eventFallback);
  return { loopId, data };
}
function applyEventFallback(data, fallback) {
  const assignIfMissing = (key) => {
    const value = fallback[key];
    if (value !== void 0 && data[key] === void 0) {
      data[key] = value;
    }
  };
  assignIfMissing("iteration");
  assignIfMissing("promise");
  assignIfMissing("promise_matched");
  assignIfMissing("test_status");
  assignIfMissing("checklist_status");
  assignIfMissing("evidence_status");
  assignIfMissing("approval_status");
  assignIfMissing("completion_ok");
  assignIfMissing("started_at");
  assignIfMissing("ended_at");
}
async function loadEventFallback(loopDir) {
  const eventsPath = path4.join(loopDir, "events.jsonl");
  if (!await fileExists(eventsPath)) {
    return {};
  }
  let raw;
  try {
    raw = await fs3.readFile(eventsPath, "utf8");
  } catch {
    return {};
  }
  const lines = raw.trim().split("\n");
  const fallback = {};
  const pending = /* @__PURE__ */ new Set([
    "iteration",
    "promise",
    "promise_matched",
    "test_status",
    "checklist_status",
    "evidence_status",
    "approval_status",
    "completion_ok",
    "started_at",
    "ended_at"
  ]);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index]?.trim();
    if (!line) {
      continue;
    }
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (pending.has("iteration") && typeof event.iteration === "number") {
      fallback.iteration = String(event.iteration);
      pending.delete("iteration");
    }
    const data = isRecord(event.data) ? event.data : {};
    if (event.event === "promise_checked") {
      if (pending.has("promise")) {
        const text = readString(data.text);
        const expected = readString(data.expected);
        if (text || expected) {
          fallback.promise = text ?? expected;
          pending.delete("promise");
        }
      }
      if (pending.has("promise_matched")) {
        const matched = readBoolean(data.matched);
        if (matched !== void 0) {
          fallback.promise_matched = matched ? "true" : "false";
          pending.delete("promise_matched");
        }
      }
    }
    if (event.event === "tests_end" && pending.has("test_status")) {
      const status = readString(data.status);
      if (status) {
        fallback.test_status = status;
        pending.delete("test_status");
      }
    }
    if (event.event === "checklist_end" && pending.has("checklist_status")) {
      const status = readString(data.status);
      if (status) {
        fallback.checklist_status = status;
        pending.delete("checklist_status");
      }
    }
    if (event.event === "evidence_end" && pending.has("evidence_status")) {
      const status = readString(data.status);
      if (status) {
        fallback.evidence_status = status;
        pending.delete("evidence_status");
      }
    }
    if (event.event === "gates_evaluated") {
      if (pending.has("test_status")) {
        const status = readString(data.tests);
        if (status) {
          fallback.test_status = status;
          pending.delete("test_status");
        }
      }
      if (pending.has("checklist_status")) {
        const status = readString(data.checklist);
        if (status) {
          fallback.checklist_status = status;
          pending.delete("checklist_status");
        }
      }
      if (pending.has("evidence_status")) {
        const status = readString(data.evidence);
        if (status) {
          fallback.evidence_status = status;
          pending.delete("evidence_status");
        }
      }
      if (pending.has("approval_status")) {
        const status = readString(data.approval);
        if (status) {
          fallback.approval_status = status;
          pending.delete("approval_status");
        }
      }
    }
    if (event.event === "iteration_start" && pending.has("started_at")) {
      const startedAt = readString(data.started_at) ?? readString(event.timestamp);
      if (startedAt) {
        fallback.started_at = startedAt;
        pending.delete("started_at");
      }
    }
    if (event.event === "iteration_end") {
      if (pending.has("ended_at")) {
        const endedAt = readString(data.ended_at) ?? readString(event.timestamp);
        if (endedAt) {
          fallback.ended_at = endedAt;
          pending.delete("ended_at");
        }
      }
      if (pending.has("completion_ok")) {
        const completion = readBoolean(data.completion);
        if (completion !== void 0) {
          fallback.completion_ok = completion ? "true" : "false";
          pending.delete("completion_ok");
        }
      }
    }
    if (pending.size === 0) {
      break;
    }
  }
  return fallback;
}
function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
function readString(value) {
  return typeof value === "string" && value.trim() ? value : void 0;
}
function readBoolean(value) {
  return typeof value === "boolean" ? value : void 0;
}

// src/lib/payload.ts
async function buildPrototypesPayload(params) {
  const [views, superloop] = await Promise.all([
    listPrototypes(params.repoRoot),
    loadSuperloopData({ repoRoot: params.repoRoot, loopId: params.loopId })
  ]);
  const renderedViews = views.map((view) => renderView(view, superloop.data));
  return {
    views: renderedViews,
    loopId: superloop.loopId,
    data: superloop.data,
    updatedAt: (/* @__PURE__ */ new Date()).toISOString()
  };
}
function renderView(view, data) {
  const versions = view.versions.map((version) => ({
    ...version,
    rendered: injectBindings(version.content, data)
  }));
  const latest = versions[versions.length - 1];
  return {
    name: view.name,
    description: view.description,
    versions,
    latest
  };
}

// src/lib/watch.ts
import fs4 from "fs";
import path5 from "path";
function watchPaths(paths, onChange) {
  const watchers = [];
  const notify = debounce(onChange, 30);
  const watchedDirs = /* @__PURE__ */ new Set();
  function handleChange(dir, filename) {
    notify();
    if (!filename) {
      return;
    }
    const name = filename.toString();
    if (!name) {
      return;
    }
    const fullPath = path5.join(dir, name);
    if (watchedDirs.has(fullPath)) {
      return;
    }
    try {
      if (fs4.existsSync(fullPath) && fs4.statSync(fullPath).isDirectory()) {
        scanDirs(fullPath);
      }
    } catch {
    }
  }
  function watchDir(dir) {
    if (watchedDirs.has(dir) || !fs4.existsSync(dir)) {
      return;
    }
    try {
      const watcher = fs4.watch(dir, (_event, filename) => {
        handleChange(dir, filename);
      });
      watchers.push(watcher);
      watchedDirs.add(dir);
    } catch {
    }
  }
  function scanDirs(root) {
    if (!fs4.existsSync(root)) {
      return;
    }
    watchDir(root);
    try {
      const entries = fs4.readdirSync(root, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory()) {
          scanDirs(path5.join(root, entry.name));
        }
      }
    } catch {
    }
  }
  for (const watchPath of paths) {
    if (!fs4.existsSync(watchPath)) {
      continue;
    }
    try {
      const watcher = fs4.watch(watchPath, { recursive: true }, () => {
        notify();
      });
      watchers.push(watcher);
    } catch {
      scanDirs(watchPath);
    }
  }
  return {
    close: () => {
      for (const watcher of watchers) {
        watcher.close();
      }
    }
  };
}
function debounce(callback, waitMs) {
  let timeout = null;
  return () => {
    if (timeout) {
      clearTimeout(timeout);
    }
    timeout = setTimeout(() => {
      timeout = null;
      callback();
    }, waitMs);
  };
}

// src/dev-server.ts
async function startDevServer(options) {
  const packageRoot = resolvePackageRoot(import.meta.url);
  const webRoot = path6.join(packageRoot, "src", "web");
  const distWebRoot = path6.join(packageRoot, "dist", "web");
  const indexHtmlPath = path6.join(webRoot, "index.html");
  const clients = /* @__PURE__ */ new Set();
  const server = http.createServer(async (req, res) => {
    if (!req.url) {
      res.writeHead(400);
      res.end();
      return;
    }
    const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
    if (url.pathname === "/events") {
      res.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive"
      });
      res.write("\n");
      clients.add(res);
      req.on("close", () => {
        clients.delete(res);
      });
      return;
    }
    if (url.pathname === "/api/prototypes") {
      const payload = await buildPrototypesPayload({
        repoRoot: options.repoRoot,
        loopId: options.loopId
      });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(payload));
      return;
    }
    if (url.pathname === "/" || url.pathname === "/index.html") {
      const html = await fs5.readFile(indexHtmlPath, "utf8");
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(html);
      return;
    }
    if (url.pathname.startsWith("/main")) {
      const filePath = path6.join(distWebRoot, url.pathname.replace("/", ""));
      if (!await fileExists(filePath)) {
        res.writeHead(503, { "Content-Type": "text/plain" });
        res.end("Web bundle not ready. Waiting for build...");
        return;
      }
      const contentType = url.pathname.endsWith(".map") ? "application/json" : "text/javascript";
      res.writeHead(200, { "Content-Type": contentType });
      res.end(await fs5.readFile(filePath));
      return;
    }
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
  });
  await new Promise((resolve) => {
    server.listen(options.port, options.host, () => resolve());
  });
  const address = `http://${options.host}:${options.port}`;
  console.log(`Superloop UI dev server running at ${address}`);
  if (options.open) {
    openBrowser(address);
  }
  const buildProcess = spawn("bunx", ["tsup", "--watch", "--config", "tsup.config.ts"], {
    cwd: packageRoot,
    stdio: "inherit"
  });
  const broadcast = async () => {
    const payload = await buildPrototypesPayload({
      repoRoot: options.repoRoot,
      loopId: options.loopId
    });
    broadcastEvent(clients, "data", payload);
  };
  const prototypesRoot = resolvePrototypesRoot(options.repoRoot);
  const loopsRoot = resolveLoopsRoot(options.repoRoot);
  const loopDir = options.loopId ? resolveLoopDir(options.repoRoot, options.loopId) : void 0;
  await fs5.mkdir(prototypesRoot, { recursive: true });
  const dataWatcher = watchPaths(
    [prototypesRoot, loopsRoot, loopDir].filter((value) => Boolean(value)),
    () => {
      void broadcast();
    }
  );
  const bundleWatcher = watchPaths([distWebRoot], () => {
    broadcastEvent(clients, "reload", { reason: "bundle" });
  });
  const shutdown = () => {
    dataWatcher.close();
    bundleWatcher.close();
    for (const client of clients) {
      client.end();
    }
    buildProcess.kill();
    server.close();
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}
function broadcastEvent(clients, event, payload) {
  const body = `event: ${event}
data: ${JSON.stringify(payload)}

`;
  for (const client of clients) {
    client.write(body);
  }
}
function openBrowser(url) {
  const platform = process.platform;
  if (platform === "darwin") {
    spawn("open", [url], { stdio: "ignore" });
    return;
  }
  if (platform === "win32") {
    spawn("cmd", ["/c", "start", url], { stdio: "ignore" });
    return;
  }
  spawn("xdg-open", [url], { stdio: "ignore" });
}

// src/commands/dev.ts
async function devCommand(params) {
  await startDevServer({
    repoRoot: params.repoRoot,
    loopId: params.loopId,
    port: params.port,
    host: params.host,
    open: params.open
  });
}

// src/commands/export.ts
import fs6 from "fs/promises";
import path7 from "path";
import chalk from "chalk";
async function exportPrototypeCommand(params) {
  const view = await readLatestPrototype({
    repoRoot: params.repoRoot,
    viewName: params.viewName
  });
  if (!view) {
    console.log(chalk.red(`Prototype ${params.viewName} not found.`));
    return;
  }
  const version = selectVersion(view.versions, params.versionId);
  if (!version) {
    console.log(chalk.red(`Version ${params.versionId} not found.`));
    return;
  }
  const superloop = await loadSuperloopData({
    repoRoot: params.repoRoot,
    loopId: params.loopId
  });
  const rendered = injectBindings(version.content, superloop.data);
  const outDir = path7.resolve(params.outDir);
  await fs6.mkdir(outDir, { recursive: true });
  const html = buildHtml(view.name, rendered);
  const css = buildCss();
  await fs6.writeFile(path7.join(outDir, "index.html"), html, "utf8");
  await fs6.writeFile(path7.join(outDir, "styles.css"), css, "utf8");
  await fs6.writeFile(path7.join(outDir, "mockup.txt"), rendered, "utf8");
  console.log(chalk.green(`Exported scaffold to ${outDir}`));
}
function selectVersion(versions, versionId) {
  if (!versionId) {
    return versions[versions.length - 1];
  }
  return versions.find((version) => version.id === versionId) ?? versions.find((version) => version.filename === versionId);
}
function buildHtml(title, content) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(title)} - Superloop UI</title>
    <link rel="stylesheet" href="styles.css" />
  </head>
  <body>
    <main class="stage">
      <h1>${escapeHtml(title)}</h1>
      <pre class="mockup">${escapeHtml(content)}</pre>
    </main>
  </body>
</html>
`;
}
function buildCss() {
  return `:root {
  color-scheme: light;
  --bg: #0f172a;
  --panel: #0b1220;
  --text: #e2e8f0;
  --accent: #38bdf8;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-height: 100vh;
  font-family: "Space Mono", "Fira Code", "Menlo", monospace;
  background: radial-gradient(circle at top, #10213f 0%, #070b14 55%, #030507 100%);
  color: var(--text);
}

.stage {
  max-width: 960px;
  margin: 0 auto;
  padding: 64px 24px;
}

h1 {
  margin: 0 0 24px;
  font-size: 28px;
  letter-spacing: 0.04em;
}

.mockup {
  padding: 24px;
  background: var(--panel);
  border: 1px solid rgba(56, 189, 248, 0.4);
  border-radius: 16px;
  white-space: pre-wrap;
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.4);
}
`;
}
function escapeHtml(value) {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;").replace(/'/g, "&#039;");
}

// src/commands/generate.ts
import { input } from "@inquirer/prompts";
import ora from "ora";

// src/lib/templates.ts
var FRAME_WIDTH = 78;
function buildPlaceholder(viewName, description) {
  const lines = [
    `SUPERLOOP UI: ${viewName}`,
    "",
    description ? `Description: ${description}` : "Description:",
    "",
    "Replace this text with your ASCII mockup.",
    "Use bindings like {{iteration}} or {{test_status}}.",
    ""
  ];
  return renderFrame(lines);
}
function renderFrame(lines) {
  const top = `+${"-".repeat(FRAME_WIDTH)}+`;
  const body = lines.map((line) => {
    const padded = line.padEnd(FRAME_WIDTH, " ");
    return `|${padded}|`;
  });
  return [top, ...body, top].join("\n");
}

// src/commands/generate.ts
async function generatePrototype(params) {
  const description = params.description?.trim() ? params.description.trim() : await input({ message: "Describe the view you want to prototype" });
  const spinner = ora("Creating prototype...").start();
  const content = buildPlaceholder(params.viewName, description);
  const version = await createPrototypeVersion({
    repoRoot: params.repoRoot,
    viewName: params.viewName,
    content,
    description,
    prompt: description
  });
  spinner.succeed(`Prototype created at ${version.path}`);
}

// src/commands/list.ts
import chalk2 from "chalk";
async function listPrototypesCommand(params) {
  const views = await listPrototypes(params.repoRoot);
  if (views.length === 0) {
    console.log(chalk2.yellow("No prototypes found."));
    return;
  }
  for (const view of views) {
    console.log(chalk2.cyan(view.name));
    if (view.description) {
      console.log(`  ${chalk2.dim(view.description)}`);
    }
    for (const version of view.versions) {
      console.log(`  - ${version.filename} (${version.createdAt})`);
    }
  }
}

// src/commands/refine.ts
import { input as input2 } from "@inquirer/prompts";
import ora2 from "ora";
async function refinePrototype(params) {
  const spinner = ora2("Creating refinement...").start();
  const view = await readLatestPrototype({
    repoRoot: params.repoRoot,
    viewName: params.viewName
  });
  if (!view) {
    spinner.fail(`No existing prototype found for ${params.viewName}`);
    return;
  }
  const description = params.description?.trim() ? params.description.trim() : await input2({ message: "Describe the refinement you want to apply" });
  const version = await createPrototypeVersion({
    repoRoot: params.repoRoot,
    viewName: params.viewName,
    content: view.latest.content,
    description
  });
  spinner.succeed(`Refinement created at ${version.path}`);
}

// src/commands/render.ts
import chalk4 from "chalk";

// src/renderers/cli.ts
import chalk3 from "chalk";

// src/renderers/frame.ts
function buildFrame(text, title) {
  const lines = text.split("\n");
  const titleWidth = title ? title.length + 2 : 0;
  const contentWidth = Math.max(...lines.map((line) => line.length), titleWidth);
  const border = `+${"-".repeat(contentWidth + 2)}+`;
  const bodyLines = lines.map((line) => line.padEnd(contentWidth, " "));
  const titleLine = title ? ` ${title} `.padEnd(contentWidth + 2, " ") : void 0;
  return {
    contentWidth,
    border,
    titleLine,
    bodyLines
  };
}
function frameToText(frame) {
  const lines = [frame.border];
  if (frame.titleLine) {
    lines.push(`|${frame.titleLine}|`, frame.border);
  }
  for (const line of frame.bodyLines) {
    lines.push(`| ${line} |`);
  }
  lines.push(frame.border);
  return lines.join("\n");
}

// src/renderers/cli.ts
function renderCli(text, title) {
  const frame = buildFrame(text, title);
  const styledBorder = chalk3.cyan(frame.border);
  const body = frame.bodyLines.map((line) => {
    return chalk3.cyan("| ") + chalk3.white(line) + chalk3.cyan(" |");
  });
  if (frame.titleLine) {
    const titleLine = chalk3.cyan("|") + chalk3.cyan(frame.titleLine) + chalk3.cyan("|");
    return [styledBorder, titleLine, styledBorder, ...body, styledBorder].join("\n");
  }
  return [styledBorder, ...body, styledBorder].join("\n");
}

// src/renderers/tui.ts
import * as blessed from "blessed";
async function renderTui(text, title) {
  const framed = frameToText(buildFrame(text, title));
  return new Promise((resolve) => {
    const screen2 = blessed.screen({
      smartCSR: true,
      title: title ?? "Superloop UI"
    });
    const box2 = blessed.box({
      top: "center",
      left: "center",
      width: "90%",
      height: "90%",
      content: framed,
      tags: false,
      scrollable: true,
      alwaysScroll: true,
      keys: true,
      vi: true
    });
    screen2.append(box2);
    screen2.key(["q", "C-c", "escape"], () => {
      screen2.destroy();
      resolve();
    });
    screen2.render();
  });
}

// src/commands/render.ts
async function renderPrototypeCommand(params) {
  const view = await readLatestPrototype({
    repoRoot: params.repoRoot,
    viewName: params.viewName
  });
  if (!view) {
    console.log(chalk4.red(`Prototype ${params.viewName} not found.`));
    return;
  }
  const version = selectVersion2(view.versions, params.versionId);
  if (!version) {
    console.log(chalk4.red(`Version ${params.versionId} not found.`));
    return;
  }
  let content = version.content;
  if (!params.raw) {
    const superloop = await loadSuperloopData({
      repoRoot: params.repoRoot,
      loopId: params.loopId
    });
    content = injectBindings(content, superloop.data);
  }
  if (params.renderer === "tui") {
    await renderTui(content, view.name);
    return;
  }
  console.log(renderCli(content, view.name));
}
function selectVersion2(versions, versionId) {
  if (!versionId) {
    return versions[versions.length - 1];
  }
  return versions.find((version) => version.id === versionId) ?? versions.find((version) => version.filename === versionId);
}

// src/lib/names.ts
function normalizeViewName(name) {
  return name.trim().replace(/[^a-zA-Z0-9_-]/g, "-");
}

// src/cli.ts
var program = new Command();
program.name("superloop-ui").description("Superloop UI prototyping framework").option("--repo <path>", "Repo root (defaults to cwd)").option("--loop <id>", "Loop id for data binding");
program.command("generate").argument("<view>", "View name for the prototype").option("-d, --description <text>", "Natural language description").action(async (view, options) => {
  const repoRoot = resolveRepoRoot(program.opts().repo);
  const viewName = normalizeViewName(view);
  await generatePrototype({
    repoRoot,
    viewName,
    description: options.description
  });
});
program.command("refine").argument("<view>", "View name to refine").option("-d, --description <text>", "Natural language description").action(async (view, options) => {
  const repoRoot = resolveRepoRoot(program.opts().repo);
  const viewName = normalizeViewName(view);
  await refinePrototype({
    repoRoot,
    viewName,
    description: options.description
  });
});
program.command("list").description("List available prototypes").action(async () => {
  const repoRoot = resolveRepoRoot(program.opts().repo);
  await listPrototypesCommand({ repoRoot });
});
program.command("render").argument("<view>", "View name to render").option("-v, --version <id>", "Version id or filename").option("-r, --renderer <mode>", "Renderer: cli or tui", "cli").option("--raw", "Skip data binding").action(async (view, options) => {
  const repoRoot = resolveRepoRoot(program.opts().repo);
  const viewName = normalizeViewName(view);
  const renderer = options.renderer === "tui" ? "tui" : "cli";
  await renderPrototypeCommand({
    repoRoot,
    viewName,
    versionId: options.version,
    renderer,
    loopId: program.opts().loop,
    raw: Boolean(options.raw)
  });
});
program.command("export").argument("<view>", "View name to export").option("-v, --version <id>", "Version id or filename").option("-o, --out <dir>", "Output directory", "./superloop-ui-export").action(async (view, options) => {
  const repoRoot = resolveRepoRoot(program.opts().repo);
  const viewName = normalizeViewName(view);
  await exportPrototypeCommand({
    repoRoot,
    viewName,
    versionId: options.version,
    loopId: program.opts().loop,
    outDir: options.out
  });
});
program.command("dev").description("Start the WorkGrid dev server").option("-p, --port <port>", "Port", "5173").option("--host <host>", "Host", "localhost").option("--no-open", "Disable auto-open in browser").action(async (options) => {
  const repoRoot = resolveRepoRoot(program.opts().repo);
  const port = Number(options.port);
  await devCommand({
    repoRoot,
    loopId: program.opts().loop,
    port: Number.isNaN(port) ? 5173 : port,
    host: options.host,
    open: options.open
  });
});
program.parse();
//# sourceMappingURL=cli.js.map