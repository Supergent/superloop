// src/dev-server.ts
import http from "http";
import path6 from "path";
import { spawn } from "child_process";
import fs5 from "fs/promises";

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
  const views = [];
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const view = await readViewDirectory(root, entry.name);
      if (view) {
        views.push(view);
      }
      continue;
    }
    if (entry.isFile() && entry.name.endsWith(VERSION_EXTENSION)) {
      const view = await readStandalonePrototype(root, entry.name);
      if (view) {
        views.push(view);
      }
    }
  }
  return views.sort((a, b) => a.name.localeCompare(b.name));
}
async function readStandalonePrototype(root, filename) {
  const viewName = path2.basename(filename, VERSION_EXTENSION);
  const filePath = path2.join(root, filename);
  const stats = await fs2.stat(filePath);
  const content = await fs2.readFile(filePath, "utf8");
  const createdAt = formatTimestamp(stats.mtime);
  const version = {
    id: createTimestampId(stats.mtime),
    filename,
    path: filePath,
    createdAt,
    content
  };
  return {
    name: viewName,
    versions: [version],
    latest: version
  };
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
      const stats = await fs2.stat(filePath);
      const content = await fs2.readFile(filePath, "utf8");
      const createdAt = formatTimestamp(stats.mtime);
      const versionId = readVersionId(entry.name, stats.mtime);
      versions.push({
        id: versionId,
        filename: entry.name,
        path: filePath,
        createdAt,
        content
      });
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
  const checklistStatus = await readJson(path3.join(loopDir, "checklist-status.json"));
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
  startDevServer
};
//# sourceMappingURL=dev-server.js.map