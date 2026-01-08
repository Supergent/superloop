// src/dev-server.ts
import { spawn } from "child_process";
import fs6 from "fs/promises";
import http from "http";
import path6 from "path";

// src/lib/fs-utils.ts
import fs from "fs/promises";
async function fileExists(path7) {
  try {
    await fs.access(path7);
    return true;
  } catch {
    return false;
  }
}
async function readJson(path7) {
  try {
    const raw = await fs.readFile(path7, "utf8");
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
import fs2 from "fs";
import path2 from "path";
var SUPERLOOP_DIR = ".superloop";
var UI_PROTOTYPES_DIR = path2.join(SUPERLOOP_DIR, "ui", "prototypes");
var LOOPS_DIR = path2.join(SUPERLOOP_DIR, "loops");
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
import fs3 from "fs/promises";
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
  const entries = await fs3.readdir(root, { withFileTypes: true });
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
async function readViewDirectory(root, viewName) {
  const viewDir = path3.join(root, viewName);
  const entries = await fs3.readdir(viewDir, { withFileTypes: true });
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
  const stats = await fs3.stat(filePath);
  const content = await fs3.readFile(filePath, "utf8");
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
import fs4 from "fs/promises";
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
  const entries = await fs4.readdir(loopsRoot, { withFileTypes: true });
  const loopDirs = entries.filter((entry) => entry.isDirectory());
  if (loopDirs.length === 0) {
    return null;
  }
  const withStats = await Promise.all(
    loopDirs.map(async (entry) => {
      const dirPath = path4.join(loopsRoot, entry.name);
      const stats = await fs4.stat(dirPath);
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
    raw = await fs4.readFile(eventsPath, "utf8");
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
import fs5 from "fs";
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
      if (fs5.existsSync(fullPath) && fs5.statSync(fullPath).isDirectory()) {
        scanDirs(fullPath);
      }
    } catch {
    }
  }
  function watchDir(dir) {
    if (watchedDirs.has(dir) || !fs5.existsSync(dir)) {
      return;
    }
    try {
      const watcher = fs5.watch(dir, (_event, filename) => {
        handleChange(dir, filename);
      });
      watchers.push(watcher);
      watchedDirs.add(dir);
    } catch {
    }
  }
  function scanDirs(root) {
    if (!fs5.existsSync(root)) {
      return;
    }
    watchDir(root);
    try {
      const entries = fs5.readdirSync(root, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory()) {
          scanDirs(path5.join(root, entry.name));
        }
      }
    } catch {
    }
  }
  for (const watchPath of paths) {
    if (!fs5.existsSync(watchPath)) {
      continue;
    }
    try {
      const watcher = fs5.watch(watchPath, { recursive: true }, () => {
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
      const html = await fs6.readFile(indexHtmlPath, "utf8");
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
      res.end(await fs6.readFile(filePath));
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
  await fs6.mkdir(prototypesRoot, { recursive: true });
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
export {
  startDevServer
};
//# sourceMappingURL=dev-server.js.map