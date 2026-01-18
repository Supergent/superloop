import { defineConfig } from 'tsup';

export default defineConfig([
  // Main library build (both ESM and CJS)
  {
    entry: {
      index: 'src/index.ts',
    },
    format: ['esm', 'cjs'],
    dts: true,
    sourcemap: true,
    clean: true,
    splitting: false,
    treeshake: true,
  },
  // CLI build (ESM only to support import.meta)
  {
    entry: {
      cli: 'src/cli.ts',
    },
    format: ['esm'],
    dts: false, // Skip DTS for CLI to avoid CJS compatibility issues
    sourcemap: true,
    splitting: false,
    treeshake: true,
    shims: true,
    banner: {
      js: '#!/usr/bin/env node',
    },
  },
]);
