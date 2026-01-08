import fs from "node:fs";
import path from "node:path";

export type WatchHandle = {
  close: () => void;
};

export function watchPaths(paths: string[], onChange: () => void): WatchHandle {
  const watchers: fs.FSWatcher[] = [];
  const notify = debounce(onChange, 30);
  const watchedDirs = new Set<string>();

  function handleChange(dir: string, filename?: string | Buffer | null) {
    notify();

    if (!filename) {
      return;
    }

    const name = filename.toString();
    if (!name) {
      return;
    }

    const fullPath = path.join(dir, name);
    if (watchedDirs.has(fullPath)) {
      return;
    }

    try {
      if (fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory()) {
        scanDirs(fullPath);
      }
    } catch {
      // Ignore transient filesystem errors.
    }
  }

  function watchDir(dir: string) {
    if (watchedDirs.has(dir) || !fs.existsSync(dir)) {
      return;
    }

    try {
      const watcher = fs.watch(dir, (_event, filename) => {
        handleChange(dir, filename);
      });
      watchers.push(watcher);
      watchedDirs.add(dir);
    } catch {
      // Ignore directories that cannot be watched on this platform.
    }
  }

  function scanDirs(root: string) {
    if (!fs.existsSync(root)) {
      return;
    }

    watchDir(root);

    try {
      const entries = fs.readdirSync(root, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory()) {
          scanDirs(path.join(root, entry.name));
        }
      }
    } catch {
      // Ignore directories we cannot traverse.
    }
  }

  for (const watchPath of paths) {
    if (!fs.existsSync(watchPath)) {
      continue;
    }

    try {
      const watcher = fs.watch(watchPath, { recursive: true }, () => {
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

function debounce(callback: () => void, waitMs: number): () => void {
  let timeout: NodeJS.Timeout | null = null;
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
