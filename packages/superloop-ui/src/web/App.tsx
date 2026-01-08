import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useMemo, useState } from "react";

const API_PATH = "/api/prototypes";
const EVENTS_PATH = "/events";

export type RenderedPrototypeVersion = {
  id: string;
  filename: string;
  path: string;
  createdAt: string;
  content: string;
  rendered: string;
};

export type RenderedPrototypeView = {
  name: string;
  description?: string;
  versions: RenderedPrototypeVersion[];
  latest: RenderedPrototypeVersion;
};

type PrototypesPayload = {
  views: RenderedPrototypeView[];
  loopId?: string;
  data: Record<string, string>;
  updatedAt: string;
};

type RendererMode = "web" | "cli" | "tui" | "all";

export function App() {
  const [payload, setPayload] = useState<PrototypesPayload | null>(null);
  const [activeView, setActiveView] = useState<RenderedPrototypeView | null>(null);
  const [versionIndex, setVersionIndex] = useState(0);
  const [rendererMode, setRendererMode] = useState<RendererMode>("web");
  const [compareVersions, setCompareVersions] = useState(false);

  useEffect(() => {
    let isMounted = true;

    const load = async () => {
      try {
        const response = await fetch(API_PATH);
        if (!response.ok) {
          return;
        }
        const next = (await response.json()) as PrototypesPayload;
        if (isMounted) {
          setPayload(next);
        }
      } catch {
        // ignore errors while server warms up
      }
    };

    void load();
    const interval = setInterval(load, 4000);

    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, []);

  useEffect(() => {
    const events = new EventSource(EVENTS_PATH);

    events.addEventListener("data", (event) => {
      try {
        const parsed = JSON.parse((event as MessageEvent).data) as PrototypesPayload;
        setPayload(parsed);
      } catch {
        // ignore invalid payloads
      }
    });

    events.addEventListener("reload", () => {
      window.location.reload();
    });

    return () => {
      events.close();
    };
  }, []);

  useEffect(() => {
    if (!payload || !activeView) {
      return;
    }
    const updated = payload.views.find((view) => view.name === activeView.name);
    if (updated) {
      setActiveView(updated);
    } else {
      setActiveView(null);
    }
  }, [payload, activeView]);

  const cards = payload?.views ?? [];
  const selectedVersion = useMemo(() => {
    if (!activeView) {
      return null;
    }
    const index = Math.min(Math.max(versionIndex, 0), activeView.versions.length - 1);
    return activeView.versions[index];
  }, [activeView, versionIndex]);

  const handleOpen = (view: RenderedPrototypeView) => {
    setActiveView(view);
    setVersionIndex(view.versions.length - 1);
    setCompareVersions(false);
  };

  return (
    <div className="app">
      <header className="hero">
        <div>
          <p className="eyebrow">Superloop UI Prototyping</p>
          <h1>WorkGrid</h1>
          <p className="subtitle">
            Live ASCII prototypes rendered across web, CLI, and TUI styles with
            bound loop data.
          </p>
        </div>
        <div className="hero-meta">
          <div>
            <span className="meta-label">Loop</span>
            <span>{payload?.loopId ?? "Not detected"}</span>
          </div>
          <div>
            <span className="meta-label">Bindings</span>
            <span>{Object.keys(payload?.data ?? {}).length} keys</span>
          </div>
          <div>
            <span className="meta-label">Updated</span>
            <span>{payload?.updatedAt ? new Date(payload.updatedAt).toLocaleTimeString() : "--"}</span>
          </div>
        </div>
      </header>

      <section className="grid">
        {cards.length === 0 && (
          <div className="empty">
            <h2>No prototypes yet</h2>
            <p>
              Run <span className="mono">superloop-ui generate &lt;view&gt;</span> to seed
              your first ASCII mockup.
            </p>
          </div>
        )}

        {cards.map((view) => (
          <motion.button
            key={view.name}
            className="card"
            layout
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35 }}
            onClick={() => handleOpen(view)}
          >
            <div className="card-head">
              <div>
                <h3>{view.name}</h3>
                <p>{view.description ?? "No description yet"}</p>
              </div>
              <span className="badge">{view.versions.length} versions</span>
            </div>
            <pre className="preview">{formatPreview(view.latest.rendered)}</pre>
            <div className="card-foot">
              <span>Latest</span>
              <span>{view.latest.createdAt}</span>
            </div>
          </motion.button>
        ))}
      </section>

      <AnimatePresence>
        {activeView && selectedVersion && (
          <motion.div
            className="overlay"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <motion.div
              className="panel"
              layout
              initial={{ y: 20, opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              exit={{ y: 20, opacity: 0 }}
            >
              <div className="panel-header">
                <div>
                  <h2>{activeView.name}</h2>
                  <p>{activeView.description ?? "No description"}</p>
                </div>
                <button className="ghost" onClick={() => setActiveView(null)}>
                  Close
                </button>
              </div>

              <div className="panel-controls">
                <div className="toggle-group">
                  {(["web", "cli", "tui", "all"] as RendererMode[]).map((mode) => (
                    <button
                      key={mode}
                      className={rendererMode === mode ? "active" : ""}
                      onClick={() => setRendererMode(mode)}
                    >
                      {mode.toUpperCase()}
                    </button>
                  ))}
                </div>
                {activeView.versions.length > 1 && (
                  <label className="toggle">
                    <input
                      type="checkbox"
                      checked={compareVersions}
                      onChange={(event) => setCompareVersions(event.target.checked)}
                    />
                    Compare versions
                  </label>
                )}
              </div>

              {!compareVersions && (
                <div className="version-controls">
                  <span>
                    Version {versionIndex + 1} of {activeView.versions.length}
                  </span>
                  <input
                    type="range"
                    min={0}
                    max={activeView.versions.length - 1}
                    value={versionIndex}
                    onChange={(event) => setVersionIndex(Number(event.target.value))}
                  />
                  <span>{selectedVersion.createdAt}</span>
                </div>
              )}

              <div className="panel-content">
                {compareVersions ? (
                  <div className="compare-grid">
                    {activeView.versions.map((version) => (
                      <div key={version.id} className="compare-item">
                        <div className="compare-meta">
                          <span>{version.filename}</span>
                          <span>{version.createdAt}</span>
                        </div>
                        <RenderSurface content={version.rendered} mode={rendererMode} />
                      </div>
                    ))}
                  </div>
                ) : (
                  <RenderSurface content={selectedVersion.rendered} mode={rendererMode} />
                )}
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function RenderSurface({ content, mode }: { content: string; mode: RendererMode }) {
  if (mode === "all") {
    return (
      <div className="surface-grid">
        <SurfaceBlock label="Web" className="web" content={content} />
        <SurfaceBlock label="CLI" className="cli" content={content} />
        <SurfaceBlock label="TUI" className="tui" content={content} />
      </div>
    );
  }

  return <SurfaceBlock label={mode.toUpperCase()} className={mode} content={content} />;
}

function SurfaceBlock({ label, content, className }: { label: string; content: string; className: string }) {
  return (
    <div className={`surface ${className}`}>
      <div className="surface-label">{label}</div>
      <pre>{content}</pre>
    </div>
  );
}

function formatPreview(content: string): string {
  const lines = content.split("\n");
  const preview = lines.slice(0, 8).join("\n");
  if (lines.length > 8) {
    return `${preview}\n...`;
  }
  return preview;
}
