import fs from "node:fs";

export type WatchHandle = {
  close: () => void;
};

export function watchPaths(paths: string[], onChange: () => void): WatchHandle {
  const watchers: fs.FSWatcher[] = [];
  const notify = debounce(onChange, 75);

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
      const watcher = fs.watch(watchPath, () => {
        notify();
      });
      watchers.push(watcher);
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
