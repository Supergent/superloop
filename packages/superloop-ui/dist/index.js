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
import path2 from "path";

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

// src/lib/paths.ts
import path from "path";
var SUPERLOOP_DIR = ".superloop";
var UI_PROTOTYPES_DIR = path.join(SUPERLOOP_DIR, "ui", "prototypes");
var LOOPS_DIR = path.join(SUPERLOOP_DIR, "loops");
function resolvePrototypesRoot(repoRoot) {
  return path.join(repoRoot, UI_PROTOTYPES_DIR);
}
function resolveLoopsRoot(repoRoot) {
  return path.join(repoRoot, LOOPS_DIR);
}
function resolveLoopDir(repoRoot, loopId) {
  return path.join(resolveLoopsRoot(repoRoot), loopId);
}

// src/lib/prototypes.ts
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
    const viewName = path2.basename(entry.name, VERSION_EXTENSION);
    const filePath = path2.join(root, entry.name);
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
  const viewDir = path2.join(root, params.viewName);
  await fs2.mkdir(viewDir, { recursive: true });
  const timestampId = createTimestampId();
  const filename = `${timestampId}${VERSION_EXTENSION}`;
  const filePath = path2.join(viewDir, filename);
  await fs2.writeFile(filePath, params.content, "utf8");
  const metaPath = path2.join(viewDir, META_FILENAME);
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
  const viewDir = path2.join(root, params.viewName);
  const view = await fileExists(viewDir) ? await readViewDirectory(root, params.viewName) : null;
  const standaloneName = `${params.viewName}${VERSION_EXTENSION}`;
  const standalonePath = path2.join(root, standaloneName);
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
  const viewDir = path2.join(root, viewName);
  const entries = await fs2.readdir(viewDir, { withFileTypes: true });
  const versions = [];
  let description;
  for (const entry of entries) {
    if (entry.isFile() && entry.name === META_FILENAME) {
      const meta = await readJson(path2.join(viewDir, entry.name));
      description = meta?.description;
      continue;
    }
    if (entry.isFile() && entry.name.endsWith(VERSION_EXTENSION)) {
      const filePath = path2.join(viewDir, entry.name);
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
import path3 from "path";
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
      const dirPath = path3.join(loopsRoot, entry.name);
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
  const runSummary = await readJson(path3.join(loopDir, "run-summary.json"));
  const testStatus = await readJson(path3.join(loopDir, "test-status.json"));
  const checklistStatus = await readJson(
    path3.join(loopDir, "checklist-status.json")
  );
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
  return { loopId, data };
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

// src/renderers/cli.ts
import chalk from "chalk";

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
  const styledBorder = chalk.cyan(frame.border);
  const body = frame.bodyLines.map((line) => {
    return chalk.cyan("| ") + chalk.white(line) + chalk.cyan(" |");
  });
  if (frame.titleLine) {
    const titleLine = chalk.cyan("|") + chalk.cyan(frame.titleLine) + chalk.cyan("|");
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

// src/dev-server.ts
import { spawn } from "child_process";
import fs5 from "fs/promises";
import http from "http";
import path6 from "path";

// src/lib/package-root.ts
import path4 from "path";
import { fileURLToPath } from "url";
function resolvePackageRoot(metaUrl) {
  const filename = fileURLToPath(metaUrl);
  const dir = path4.dirname(filename);
  return path4.resolve(dir, "..");
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
export {
  buildPrototypesPayload,
  createPrototypeVersion,
  createTimestampId,
  formatTimestamp,
  injectBindings,
  listPrototypes,
  loadSuperloopData,
  readLatestPrototype,
  renderCli,
  renderTui,
  resolveLoopId,
  startDevServer
};
//# sourceMappingURL=index.js.map