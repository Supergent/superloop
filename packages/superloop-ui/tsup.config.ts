import { defineConfig } from "tsup";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reactPath = path.join(__dirname, "node_modules/react");
const reactDomPath = path.join(__dirname, "node_modules/react-dom");

export default defineConfig([
  {
    entry: ["src/cli.ts"],
    format: ["esm"],
    platform: "node",
    sourcemap: true,
    target: "node20",
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
    noExternal: [/./],
    esbuildOptions(options) {
      // Dedupe React to prevent multiple instances from nested packages
      options.alias = {
        "react": reactPath,
        "react-dom": reactDomPath,
        "react/jsx-runtime": path.join(reactPath, "jsx-runtime"),
        "react/jsx-dev-runtime": path.join(reactPath, "jsx-dev-runtime"),
        "react-dom/client": path.join(reactDomPath, "client"),
      };
    },
  },
  {
    entry: ["src/web/liquid-main.tsx"],
    format: ["esm"],
    platform: "browser",
    sourcemap: true,
    target: "es2020",
    outDir: "dist/web",
    splitting: false,
    noExternal: [/./],
    esbuildOptions(options) {
      // Dedupe React to prevent multiple instances from nested packages
      options.alias = {
        "react": reactPath,
        "react-dom": reactDomPath,
        "react/jsx-runtime": path.join(reactPath, "jsx-runtime"),
        "react/jsx-dev-runtime": path.join(reactPath, "jsx-dev-runtime"),
        "react-dom/client": path.join(reactDomPath, "client"),
      };
    },
  },
]);
