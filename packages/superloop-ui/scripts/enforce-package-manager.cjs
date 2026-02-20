#!/usr/bin/env node

const userAgent = process.env.npm_config_user_agent || "";

if (!userAgent.includes("bun/")) {
  console.error("error: superloop-ui must be installed with bun to keep bun.lock deterministic");
  console.error("hint: run `bun install --frozen-lockfile` in packages/superloop-ui");
  process.exit(1);
}