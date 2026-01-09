#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const http = require("http");
const { URL } = require("url");

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

function resolvePath(repo, filePath) {
  if (!filePath) return null;
  if (path.isAbsolute(filePath)) {
    return filePath;
  }
  return path.resolve(repo, filePath);
}

function mimeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
      return "application/javascript; charset=utf-8";
    case ".css":
      return "text/css; charset=utf-8";
    case ".json":
      return "application/json; charset=utf-8";
    case ".map":
      return "application/json; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".ico":
      return "image/x-icon";
    case ".woff":
      return "font/woff";
    case ".woff2":
      return "font/woff2";
    default:
      return "application/octet-stream";
  }
}

function serveStatic(rootDir) {
  const server = http.createServer((req, res) => {
    const requestUrl = new URL(req.url || "/", "http://localhost");
    const rawPath = decodeURIComponent(requestUrl.pathname);
    const safePath = rawPath.replace(/^\/+/, "");
    const filePath = path.join(rootDir, safePath);
    const resolved = path.resolve(filePath);

    if (!resolved.startsWith(path.resolve(rootDir))) {
      res.statusCode = 403;
      res.end("forbidden");
      return;
    }

    let target = resolved;
    if (fs.existsSync(resolved) && fs.statSync(resolved).isDirectory()) {
      target = path.join(resolved, "index.html");
    }

    if (!fs.existsSync(target)) {
      res.statusCode = 404;
      res.end("not found");
      return;
    }

    const contentType = mimeFor(target);
    res.writeHead(200, { "Content-Type": contentType });
    fs.createReadStream(target).pipe(res);
  });

  return server;
}

async function runSmokeTest(config, repo) {
  const result = {
    ok: true,
    entry: config.entry || null,
    url: null,
    checks: [],
    errors: [],
    console_errors: [],
    screenshot: config.screenshot_path || null,
    generated_at: new Date().toISOString(),
  };

  let playwright;
  try {
    playwright = require("playwright");
  } catch (error) {
    if (config.optional === true) {
      result.ok = true;
      result.skipped = true;
      result.errors.push("playwright_not_installed");
      return result;
    }
    result.ok = false;
    result.errors.push("playwright_not_installed");
    result.message = error.message;
    return result;
  }

  if (!config.entry) {
    result.ok = false;
    result.errors.push("missing_entry");
    return result;
  }

  const entryPath = resolvePath(repo, config.entry);
  if (!entryPath || !fs.existsSync(entryPath)) {
    result.ok = false;
    result.errors.push(`entry_not_found:${config.entry}`);
    return result;
  }

  const webRoot = config.web_root
    ? resolvePath(repo, config.web_root)
    : path.dirname(entryPath);
  const entryRel = path.relative(webRoot, entryPath).split(path.sep).join("/");
  const server = serveStatic(webRoot);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const url = `http://127.0.0.1:${port}/${entryRel}`;
  result.url = url;

  let browser;
  try {
    browser = await playwright.chromium.launch({
      headless: config.headless !== false,
    });
    const page = await browser.newPage();

    page.on("pageerror", (error) => {
      result.errors.push(`page_error:${error.message}`);
    });
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        result.console_errors.push(msg.text());
      }
    });

    try {
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: config.timeout_ms || 15000 });
    } catch (error) {
      result.ok = false;
      result.errors.push(`navigation_failed:${error.message}`);
    }

    const checks = Array.isArray(config.checks) ? config.checks : [];
    for (const check of checks) {
      if (!check) continue;
      if (check.selector) {
        const locator = page.locator(check.selector);
        if (check.should === "be_visible") {
          const visible = await locator.first().isVisible().catch(() => false);
          if (!visible) {
            result.ok = false;
            result.errors.push(`selector_not_visible:${check.selector}`);
          }
        } else {
          const count = await locator.count().catch(() => 0);
          if (count === 0) {
            result.ok = false;
            result.errors.push(`selector_not_found:${check.selector}`);
          }
        }
        result.checks.push({ selector: check.selector, should: check.should || "exist" });
        continue;
      }
      if (check.text) {
        const locator = page.locator(`text=${check.text}`);
        if (check.should === "be_visible") {
          const visible = await locator.first().isVisible().catch(() => false);
          if (!visible) {
            result.ok = false;
            result.errors.push(`text_not_visible:${check.text}`);
          }
        } else {
          const count = await locator.count().catch(() => 0);
          if (count === 0) {
            result.ok = false;
            result.errors.push(`text_not_found:${check.text}`);
          }
        }
        result.checks.push({ text: check.text, should: check.should || "exist" });
      }
    }

    if (config.fail_on_console_error !== false && result.console_errors.length > 0) {
      result.ok = false;
    }

    if (config.screenshot_path) {
      const screenshotPath = resolvePath(repo, config.screenshot_path);
      fs.mkdirSync(path.dirname(screenshotPath), { recursive: true });
      await page.screenshot({ path: screenshotPath, fullPage: true });
      result.screenshot = screenshotPath;
    }
  } finally {
    if (browser) {
      await browser.close();
    }
    server.close();
  }

  return result;
}

async function main() {
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

  const result = await runSmokeTest(config || {}, args.repo);
  console.log(JSON.stringify(result));
  process.exit(result.ok ? 0 : 1);
}

main().catch((error) => {
  console.log(
    JSON.stringify({
      ok: false,
      error: "smoke_test_failed",
      message: error.message,
    })
  );
  process.exit(1);
});
