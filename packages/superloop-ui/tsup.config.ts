import { defineConfig } from "tsup";

export default defineConfig([
  {
    entry: ["src/cli.ts"],
    format: ["esm"],
    platform: "node",
    sourcemap: true,
    target: "node20",
    clean: true,
    banner: {
      js: "#!/usr/bin/env node",
    },
    outDir: "dist",
  },
  {
    entry: ["src/index.ts"],
    format: ["esm"],
    platform: "node",
    sourcemap: true,
    target: "node20",
    outDir: "dist",
  },
  {
    entry: ["src/dev-server.ts"],
    format: ["esm"],
    platform: "node",
    sourcemap: true,
    target: "node20",
    outDir: "dist",
  },
  {
    entry: ["src/build-assets.ts"],
    format: ["esm"],
    platform: "node",
    target: "node20",
    outDir: "dist",
  },
  {
    entry: ["src/web/main.tsx"],
    format: ["esm"],
    platform: "browser",
    sourcemap: true,
    target: "es2020",
    outDir: "dist/web",
    splitting: false,
  },
]);
