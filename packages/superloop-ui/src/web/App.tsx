/**
 * @deprecated WorkGrid (ASCII Prototype Viewer) - Legacy
 *
 * This component is deprecated. Use the Liquid Dashboard instead:
 * - Navigate to /liquid for the new dashboard
 * - Use @superloop-ui/liquid/Dashboard for programmatic access
 *
 * The liquid dashboard provides:
 * - Typed UITree components (not ASCII)
 * - Version history with timeline navigation
 * - Live data binding with superloop context
 * - Full component validation
 */

import { AnimatePresence, LayoutGroup, motion } from "framer-motion";
import { type ChangeEvent, useEffect, useMemo, useState } from "react";

import { PrototypeGrid } from "../components/PrototypeGrid.js";
import { RenderSurface, type RendererMode } from "../renderers/web.js";
import type { PrototypesPayload, RenderedPrototypeView } from "./types.js";

const API_PATH = "/api/prototypes";
const EVENTS_PATH = "/events";

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

    events.addEventListener("data", (event: MessageEvent) => {
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
      setVersionIndex((previous) => {
        const previousLast = activeView.versions.length - 1;
        const nextLast = updated.versions.length - 1;
        const wasOnLatest = previous >= previousLast;
        return wasOnLatest ? nextLast : Math.min(previous, nextLast);
      });
    } else {
      setActiveView(null);
    }
  }, [payload, activeView]);

  const cards: RenderedPrototypeView[] = payload?.views ?? [];
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

  const handleCompareToggle = (event: ChangeEvent<HTMLInputElement>) => {
    setCompareVersions(event.currentTarget.checked);
  };

  const handleVersionChange = (event: ChangeEvent<HTMLInputElement>) => {
    setVersionIndex(Number(event.currentTarget.value));
  };

  const handleVersionSelect = (index: number) => {
    setVersionIndex(index);
  };

  return (
    <div className="app">
      <header className="hero">
        <div>
          <p className="eyebrow">Superloop UI Prototyping</p>
          <h1>WorkGrid</h1>
          <p className="subtitle">
            Live ASCII prototypes rendered across web, CLI, and TUI styles with bound loop data.
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
            <span>
              {payload?.updatedAt ? new Date(payload.updatedAt).toLocaleTimeString() : "--"}
            </span>
          </div>
        </div>
      </header>

      <LayoutGroup>
        <PrototypeGrid views={cards} onOpen={handleOpen} />

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
                layoutId={`card-${activeView.name}`}
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
                  <button type="button" className="ghost" onClick={() => setActiveView(null)}>
                    Close
                  </button>
                </div>

                <div className="panel-controls">
                  <div className="toggle-group">
                    {(["web", "cli", "tui", "all"] as RendererMode[]).map((mode) => (
                      <button
                        key={mode}
                        type="button"
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
                        onChange={handleCompareToggle}
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
                      onChange={handleVersionChange}
                    />
                    <span>{selectedVersion.createdAt}</span>
                  </div>
                )}

                {!compareVersions && activeView.versions.length > 1 && (
                  <div className="version-timeline">
                    {activeView.versions.map((version, index) => (
                      <button
                        key={version.id}
                        type="button"
                        title={version.filename}
                        className={`version-chip${index === versionIndex ? " active" : ""}`}
                        onClick={() => handleVersionSelect(index)}
                      >
                        <span>V{index + 1}</span>
                        <span>{version.createdAt}</span>
                      </button>
                    ))}
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
                          <RenderSurface
                            content={version.rendered}
                            mode={rendererMode}
                            title={activeView.name}
                          />
                        </div>
                      ))}
                    </div>
                  ) : (
                    <RenderSurface
                      content={selectedVersion.rendered}
                      mode={rendererMode}
                      title={activeView.name}
                    />
                  )}
                </div>
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>
      </LayoutGroup>
    </div>
  );
}
