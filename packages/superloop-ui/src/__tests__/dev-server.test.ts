import { afterEach, beforeEach, describe, expect, it } from "vitest";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";

import { startDevServer, type DevServerHandle } from "../dev-server";

type HttpResponse = {
  status: number;
  headers: http.IncomingHttpHeaders;
  body: string;
};

function requestJson(baseUrl: string, method: string, route: string, payload?: unknown): Promise<HttpResponse> {
  const url = new URL(route, baseUrl);

  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        method,
        hostname: url.hostname,
        port: Number(url.port),
        path: `${url.pathname}${url.search}`,
        headers: payload
          ? {
              "Content-Type": "application/json",
            }
          : undefined,
      },
      (res) => {
        let body = "";
        res.on("data", (chunk) => {
          body += chunk.toString();
        });
        res.on("end", () => {
          resolve({
            status: res.statusCode ?? 0,
            headers: res.headers,
            body,
          });
        });
      },
    );

    req.on("error", reject);
    if (payload !== undefined) {
      req.write(JSON.stringify(payload));
    }
    req.end();
  });
}

describe("dev server API contract", () => {
  let repoRoot: string;
  let server: DevServerHandle;
  const loopId = "contract-loop";

  beforeEach(async () => {
    repoRoot = await fs.mkdtemp(path.join(os.tmpdir(), "superloop-ui-server-"));

    const loopDir = path.join(repoRoot, ".superloop", "loops", loopId);
    await fs.mkdir(loopDir, { recursive: true });
    await fs.mkdir(path.join(repoRoot, ".superloop"), { recursive: true });

    await fs.writeFile(
      path.join(repoRoot, ".superloop", "state.json"),
      JSON.stringify({ active: true, current_loop_id: loopId }, null, 2),
      "utf8",
    );

    await fs.writeFile(
      path.join(loopDir, "run-summary.json"),
      JSON.stringify(
        {
          loop_id: loopId,
          updated_at: "2026-02-20T12:00:00Z",
          entries: [{ iteration: 1, promise: { matched: false }, completion_ok: false }],
        },
        null,
        2,
      ),
      "utf8",
    );

    server = await startDevServer({
      repoRoot,
      loopId,
      port: 0,
      host: "127.0.0.1",
      open: false,
      watch: false,
    });
  });

  afterEach(async () => {
    await server.close();
    await fs.rm(repoRoot, { recursive: true, force: true });
  });

  it("serves /api/liquid/context", async () => {
    const res = await requestJson(server.url, "GET", "/api/liquid/context");

    expect(res.status).toBe(200);
    expect(res.headers["content-type"]).toContain("application/json");

    const body = JSON.parse(res.body);
    expect(body.loopId).toBe(loopId);
    expect(body.iteration).toBe(1);
    expect(body.active).toBe(true);
  });

  it("supports override lifecycle", async () => {
    const before = await requestJson(server.url, "GET", "/api/liquid/override");
    expect(before.status).toBe(204);

    const tree = {
      root: "main",
      elements: {
        main: {
          key: "main",
          type: "Card",
          props: { title: "override" },
        },
      },
    };

    const posted = await requestJson(server.url, "POST", "/api/liquid/override", { tree });
    expect(posted.status).toBe(200);

    const current = await requestJson(server.url, "GET", "/api/liquid/override");
    expect(current.status).toBe(200);
    expect(JSON.parse(current.body)).toEqual(tree);

    const deleted = await requestJson(server.url, "DELETE", "/api/liquid/override");
    expect(deleted.status).toBe(200);

    const after = await requestJson(server.url, "GET", "/api/liquid/override");
    expect(after.status).toBe(204);
  });

  it("supports listing and saving liquid views", async () => {
    const initial = await requestJson(server.url, "GET", "/api/liquid/views");
    expect(initial.status).toBe(200);
    expect(JSON.parse(initial.body)).toEqual([]);

    const created = await requestJson(
      server.url,
      "POST",
      "/api/liquid/views/qa-dashboard",
      {
        tree: {
          root: "main",
          elements: {
            main: {
              key: "main",
              type: "Card",
              props: { title: "qa" },
            },
          },
        },
        prompt: "Create QA dashboard",
      },
    );

    expect(created.status).toBe(201);

    const listed = await requestJson(server.url, "GET", "/api/liquid/views");
    expect(listed.status).toBe(200);
    const views = JSON.parse(listed.body);
    expect(Array.isArray(views)).toBe(true);
    expect(views.length).toBe(1);
    expect(views[0].name).toBe("qa-dashboard");
  });
});