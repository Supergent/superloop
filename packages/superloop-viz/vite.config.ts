import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync, existsSync, readdirSync } from 'fs';
import { join, resolve } from 'path';

/**
 * Vite plugin to serve Superloop data from the filesystem.
 * Exposes /__api/superloop/* endpoints that read from .superloop directory.
 */
function superloopDataPlugin(): Plugin {
  // Resolve .superloop directory relative to repo root (2 levels up from this package)
  const repoRoot = resolve(__dirname, '../..');
  const superloopDir = join(repoRoot, '.superloop');

  return {
    name: 'superloop-data',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (!req.url?.startsWith('/__api/superloop')) {
          return next();
        }

        res.setHeader('Content-Type', 'application/json');

        try {
          // GET /__api/superloop/state - Current state
          if (req.url === '/__api/superloop/state') {
            const statePath = join(superloopDir, 'state.json');
            if (existsSync(statePath)) {
              const data = readFileSync(statePath, 'utf-8');
              res.end(data);
            } else {
              res.end(JSON.stringify({ active: false, current_loop_id: null }));
            }
            return;
          }

          // GET /__api/superloop/loops - List available loops
          if (req.url === '/__api/superloop/loops') {
            const loopsDir = join(superloopDir, 'loops');
            if (existsSync(loopsDir)) {
              const loops = readdirSync(loopsDir, { withFileTypes: true })
                .filter((d) => d.isDirectory())
                .map((d) => d.name);
              res.end(JSON.stringify({ loops }));
            } else {
              res.end(JSON.stringify({ loops: [] }));
            }
            return;
          }

          // GET /__api/superloop/loops/:loopId/run-summary
          const runSummaryMatch = req.url.match(
            /^\/__api\/superloop\/loops\/([^/]+)\/run-summary$/
          );
          if (runSummaryMatch) {
            const loopId = runSummaryMatch[1];
            const summaryPath = join(superloopDir, 'loops', loopId, 'run-summary.json');
            if (existsSync(summaryPath)) {
              const data = readFileSync(summaryPath, 'utf-8');
              res.end(data);
            } else {
              res.statusCode = 404;
              res.end(JSON.stringify({ error: 'Loop not found' }));
            }
            return;
          }

          // GET /__api/superloop/loops/:loopId/artifact/:name
          const artifactMatch = req.url.match(
            /^\/__api\/superloop\/loops\/([^/]+)\/artifact\/(.+)$/
          );
          if (artifactMatch) {
            const loopId = artifactMatch[1];
            const artifactName = artifactMatch[2];
            const artifactPath = join(superloopDir, 'loops', loopId, artifactName);
            if (existsSync(artifactPath)) {
              const data = readFileSync(artifactPath, 'utf-8');
              // Return as text or JSON depending on extension
              if (artifactPath.endsWith('.json')) {
                res.end(data);
              } else {
                res.setHeader('Content-Type', 'text/plain');
                res.end(data);
              }
            } else {
              res.statusCode = 404;
              res.end(JSON.stringify({ error: 'Artifact not found' }));
            }
            return;
          }

          res.statusCode = 404;
          res.end(JSON.stringify({ error: 'Unknown endpoint' }));
        } catch (error) {
          res.statusCode = 500;
          res.end(JSON.stringify({ error: String(error) }));
        }
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), superloopDataPlugin()],
  server: {
    port: 5173,
  },
});
