import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";

import { fileExists } from "./lib/fs-utils.js";
import { resolvePackageRoot } from "./lib/package-root.js";
import { resolveLoopDir, resolveLoopsRoot, resolvePrototypesRoot } from "./lib/paths.js";
import { buildPrototypesPayload } from "./lib/payload.js";
import { watchPaths } from "./lib/watch.js";
import { loadSuperloopContext } from "./liquid/context-loader.js";

export type DevServerOptions = {
  repoRoot: string;
  loopId?: string;
  port: number;
  host: string;
  open: boolean;
};

type SseClient = http.ServerResponse;

export async function startDevServer(options: DevServerOptions): Promise<void> {
  const packageRoot = resolvePackageRoot(import.meta.url);
  const webRoot = path.join(packageRoot, "src", "web");
  const distWebRoot = path.join(packageRoot, "dist", "web");
  const indexHtmlPath = path.join(webRoot, "index.html");
  const liquidHtmlPath = path.join(webRoot, "liquid.html");

  // Store for skill-generated override tree
  let overrideTree: unknown = null;

  const clients = new Set<SseClient>();

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
        Connection: "keep-alive",
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
        loopId: options.loopId,
      });
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(payload));
      return;
    }

    // Liquid Dashboard API: Get current context
    if (url.pathname === "/api/liquid/context") {
      try {
        const context = await loadSuperloopContext({
          repoRoot: options.repoRoot,
          loopId: options.loopId,
        });
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(context));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: String(err) }));
      }
      return;
    }

    // Liquid Dashboard API: Get/Set override tree
    if (url.pathname === "/api/liquid/override") {
      if (req.method === "GET") {
        if (overrideTree) {
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify(overrideTree));
        } else {
          res.writeHead(204);
          res.end();
        }
        return;
      }
      if (req.method === "POST") {
        let body = "";
        req.on("data", (chunk) => (body += chunk));
        req.on("end", () => {
          try {
            overrideTree = JSON.parse(body);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ ok: true }));
          } catch {
            res.writeHead(400, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "Invalid JSON" }));
          }
        });
        return;
      }
      if (req.method === "DELETE") {
        overrideTree = null;
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true }));
        return;
      }
    }

    // Liquid Dashboard: Serve HTML
    if (url.pathname === "/liquid" || url.pathname === "/liquid/") {
      const html = await fs.readFile(liquidHtmlPath, "utf8");
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(html);
      return;
    }

    // Liquid Dashboard: Serve JS bundle
    if (url.pathname === "/liquid-main.js" || url.pathname === "/liquid-main.js.map") {
      const filePath = path.join(distWebRoot, url.pathname.replace("/", ""));
      if (!(await fileExists(filePath))) {
        res.writeHead(503, { "Content-Type": "text/plain" });
        res.end("Liquid dashboard bundle not ready. Waiting for build...");
        return;
      }
      const contentType = url.pathname.endsWith(".map") ? "application/json" : "text/javascript";
      res.writeHead(200, { "Content-Type": contentType });
      res.end(await fs.readFile(filePath));
      return;
    }

    if (url.pathname === "/" || url.pathname === "/index.html") {
      const html = await fs.readFile(indexHtmlPath, "utf8");
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(html);
      return;
    }

    if (url.pathname.startsWith("/main")) {
      const filePath = path.join(distWebRoot, url.pathname.replace("/", ""));
      if (!(await fileExists(filePath))) {
        res.writeHead(503, { "Content-Type": "text/plain" });
        res.end("Web bundle not ready. Waiting for build...");
        return;
      }
      const contentType = url.pathname.endsWith(".map") ? "application/json" : "text/javascript";
      res.writeHead(200, { "Content-Type": contentType });
      res.end(await fs.readFile(filePath));
      return;
    }

    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
  });

  await new Promise<void>((resolve) => {
    server.listen(options.port, options.host, () => resolve());
  });

  const address = `http://${options.host}:${options.port}`;
  console.log(`Superloop UI dev server running at ${address}`);

  if (options.open) {
    openBrowser(address);
  }

  const buildProcess = spawn("bunx", ["tsup", "--watch", "--config", "tsup.config.ts"], {
    cwd: packageRoot,
    stdio: "inherit",
  });

  const broadcast = async () => {
    const payload = await buildPrototypesPayload({
      repoRoot: options.repoRoot,
      loopId: options.loopId,
    });
    broadcastEvent(clients, "data", payload);
  };

  const prototypesRoot = resolvePrototypesRoot(options.repoRoot);
  const loopsRoot = resolveLoopsRoot(options.repoRoot);
  const loopDir = options.loopId ? resolveLoopDir(options.repoRoot, options.loopId) : undefined;

  await fs.mkdir(prototypesRoot, { recursive: true });

  const dataWatcher = watchPaths(
    [prototypesRoot, loopsRoot, loopDir].filter((value): value is string => Boolean(value)),
    () => {
      void broadcast();
    },
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

function broadcastEvent(clients: Set<SseClient>, event: string, payload: unknown) {
  const body = `event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`;
  for (const client of clients) {
    client.write(body);
  }
}

function openBrowser(url: string) {
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
