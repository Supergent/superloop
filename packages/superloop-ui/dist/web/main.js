// src/web/main.tsx
import { createRoot } from "react-dom/client";

// src/web/App.tsx
import { AnimatePresence, motion as motion2 } from "framer-motion";
import { useEffect, useMemo, useState } from "react";

// src/components/PrototypeGrid.tsx
import { motion } from "framer-motion";
import { jsx, jsxs } from "react/jsx-runtime";
function PrototypeGrid({ views, onOpen }) {
  return /* @__PURE__ */ jsxs("section", { className: "grid", children: [
    views.length === 0 && /* @__PURE__ */ jsxs("div", { className: "empty", children: [
      /* @__PURE__ */ jsx("h2", { children: "No prototypes yet" }),
      /* @__PURE__ */ jsxs("p", { children: [
        "Run ",
        /* @__PURE__ */ jsx("span", { className: "mono", children: "superloop-ui generate <view>" }),
        " to seed your first ASCII mockup."
      ] })
    ] }),
    views.map((view) => /* @__PURE__ */ jsxs(
      motion.button,
      {
        className: "card",
        layout: true,
        initial: { opacity: 0, y: 18 },
        animate: { opacity: 1, y: 0 },
        transition: { duration: 0.35 },
        onClick: () => onOpen(view),
        children: [
          /* @__PURE__ */ jsxs("div", { className: "card-head", children: [
            /* @__PURE__ */ jsxs("div", { children: [
              /* @__PURE__ */ jsx("h3", { children: view.name }),
              /* @__PURE__ */ jsx("p", { children: view.description ?? "No description yet" })
            ] }),
            /* @__PURE__ */ jsxs("span", { className: "badge", children: [
              view.versions.length,
              " versions"
            ] })
          ] }),
          /* @__PURE__ */ jsx("pre", { className: "preview", children: formatPreview(view.latest.rendered) }),
          /* @__PURE__ */ jsxs("div", { className: "card-foot", children: [
            /* @__PURE__ */ jsx("span", { children: "Latest" }),
            /* @__PURE__ */ jsx("span", { children: view.latest.createdAt })
          ] })
        ]
      },
      view.name
    ))
  ] });
}
function formatPreview(content) {
  const lines = content.split("\n");
  const preview = lines.slice(0, 8).join("\n");
  if (lines.length > 8) {
    return `${preview}
...`;
  }
  return preview;
}

// src/renderers/web.tsx
import { jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
function RenderSurface({ content, mode }) {
  if (mode === "all") {
    return /* @__PURE__ */ jsxs2("div", { className: "surface-grid", children: [
      /* @__PURE__ */ jsx2(SurfaceBlock, { label: "Web", className: "web", content }),
      /* @__PURE__ */ jsx2(SurfaceBlock, { label: "CLI", className: "cli", content }),
      /* @__PURE__ */ jsx2(SurfaceBlock, { label: "TUI", className: "tui", content })
    ] });
  }
  return /* @__PURE__ */ jsx2(SurfaceBlock, { label: mode.toUpperCase(), className: mode, content });
}
function SurfaceBlock({
  label,
  content,
  className
}) {
  return /* @__PURE__ */ jsxs2("div", { className: `surface ${className}`, children: [
    /* @__PURE__ */ jsx2("div", { className: "surface-label", children: label }),
    /* @__PURE__ */ jsx2("pre", { children: content })
  ] });
}

// src/web/App.tsx
import { jsx as jsx3, jsxs as jsxs3 } from "react/jsx-runtime";
var API_PATH = "/api/prototypes";
var EVENTS_PATH = "/events";
function App() {
  const [payload, setPayload] = useState(null);
  const [activeView, setActiveView] = useState(null);
  const [versionIndex, setVersionIndex] = useState(0);
  const [rendererMode, setRendererMode] = useState("web");
  const [compareVersions, setCompareVersions] = useState(false);
  useEffect(() => {
    let isMounted = true;
    const load = async () => {
      try {
        const response = await fetch(API_PATH);
        if (!response.ok) {
          return;
        }
        const next = await response.json();
        if (isMounted) {
          setPayload(next);
        }
      } catch {
      }
    };
    void load();
    const interval = setInterval(load, 4e3);
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, []);
  useEffect(() => {
    const events = new EventSource(EVENTS_PATH);
    events.addEventListener("data", (event) => {
      try {
        const parsed = JSON.parse(event.data);
        setPayload(parsed);
      } catch {
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
  const handleOpen = (view) => {
    setActiveView(view);
    setVersionIndex(view.versions.length - 1);
    setCompareVersions(false);
  };
  const handleCompareToggle = (event) => {
    setCompareVersions(event.currentTarget.checked);
  };
  const handleVersionChange = (event) => {
    setVersionIndex(Number(event.currentTarget.value));
  };
  return /* @__PURE__ */ jsxs3("div", { className: "app", children: [
    /* @__PURE__ */ jsxs3("header", { className: "hero", children: [
      /* @__PURE__ */ jsxs3("div", { children: [
        /* @__PURE__ */ jsx3("p", { className: "eyebrow", children: "Superloop UI Prototyping" }),
        /* @__PURE__ */ jsx3("h1", { children: "WorkGrid" }),
        /* @__PURE__ */ jsx3("p", { className: "subtitle", children: "Live ASCII prototypes rendered across web, CLI, and TUI styles with bound loop data." })
      ] }),
      /* @__PURE__ */ jsxs3("div", { className: "hero-meta", children: [
        /* @__PURE__ */ jsxs3("div", { children: [
          /* @__PURE__ */ jsx3("span", { className: "meta-label", children: "Loop" }),
          /* @__PURE__ */ jsx3("span", { children: payload?.loopId ?? "Not detected" })
        ] }),
        /* @__PURE__ */ jsxs3("div", { children: [
          /* @__PURE__ */ jsx3("span", { className: "meta-label", children: "Bindings" }),
          /* @__PURE__ */ jsxs3("span", { children: [
            Object.keys(payload?.data ?? {}).length,
            " keys"
          ] })
        ] }),
        /* @__PURE__ */ jsxs3("div", { children: [
          /* @__PURE__ */ jsx3("span", { className: "meta-label", children: "Updated" }),
          /* @__PURE__ */ jsx3("span", { children: payload?.updatedAt ? new Date(payload.updatedAt).toLocaleTimeString() : "--" })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsx3(PrototypeGrid, { views: cards, onOpen: handleOpen }),
    /* @__PURE__ */ jsx3(AnimatePresence, { children: activeView && selectedVersion && /* @__PURE__ */ jsx3(
      motion2.div,
      {
        className: "overlay",
        initial: { opacity: 0 },
        animate: { opacity: 1 },
        exit: { opacity: 0 },
        children: /* @__PURE__ */ jsxs3(
          motion2.div,
          {
            className: "panel",
            layout: true,
            initial: { y: 20, opacity: 0 },
            animate: { y: 0, opacity: 1 },
            exit: { y: 20, opacity: 0 },
            children: [
              /* @__PURE__ */ jsxs3("div", { className: "panel-header", children: [
                /* @__PURE__ */ jsxs3("div", { children: [
                  /* @__PURE__ */ jsx3("h2", { children: activeView.name }),
                  /* @__PURE__ */ jsx3("p", { children: activeView.description ?? "No description" })
                ] }),
                /* @__PURE__ */ jsx3("button", { className: "ghost", onClick: () => setActiveView(null), children: "Close" })
              ] }),
              /* @__PURE__ */ jsxs3("div", { className: "panel-controls", children: [
                /* @__PURE__ */ jsx3("div", { className: "toggle-group", children: ["web", "cli", "tui", "all"].map((mode) => /* @__PURE__ */ jsx3(
                  "button",
                  {
                    className: rendererMode === mode ? "active" : "",
                    onClick: () => setRendererMode(mode),
                    children: mode.toUpperCase()
                  },
                  mode
                )) }),
                activeView.versions.length > 1 && /* @__PURE__ */ jsxs3("label", { className: "toggle", children: [
                  /* @__PURE__ */ jsx3("input", { type: "checkbox", checked: compareVersions, onChange: handleCompareToggle }),
                  "Compare versions"
                ] })
              ] }),
              !compareVersions && /* @__PURE__ */ jsxs3("div", { className: "version-controls", children: [
                /* @__PURE__ */ jsxs3("span", { children: [
                  "Version ",
                  versionIndex + 1,
                  " of ",
                  activeView.versions.length
                ] }),
                /* @__PURE__ */ jsx3(
                  "input",
                  {
                    type: "range",
                    min: 0,
                    max: activeView.versions.length - 1,
                    value: versionIndex,
                    onChange: handleVersionChange
                  }
                ),
                /* @__PURE__ */ jsx3("span", { children: selectedVersion.createdAt })
              ] }),
              /* @__PURE__ */ jsx3("div", { className: "panel-content", children: compareVersions ? /* @__PURE__ */ jsx3("div", { className: "compare-grid", children: activeView.versions.map((version) => /* @__PURE__ */ jsxs3("div", { className: "compare-item", children: [
                /* @__PURE__ */ jsxs3("div", { className: "compare-meta", children: [
                  /* @__PURE__ */ jsx3("span", { children: version.filename }),
                  /* @__PURE__ */ jsx3("span", { children: version.createdAt })
                ] }),
                /* @__PURE__ */ jsx3(RenderSurface, { content: version.rendered, mode: rendererMode })
              ] }, version.id)) }) : /* @__PURE__ */ jsx3(RenderSurface, { content: selectedVersion.rendered, mode: rendererMode }) })
            ]
          }
        )
      }
    ) })
  ] });
}

// src/web/styles.ts
var styles = `:root {
  color-scheme: light;
  --bg-1: #0b0f1a;
  --bg-2: #1b2336;
  --bg-3: #2f3442;
  --panel: rgba(15, 23, 42, 0.92);
  --panel-solid: #0f172a;
  --card: rgba(17, 25, 40, 0.85);
  --card-border: rgba(148, 163, 184, 0.2);
  --accent: #f59e0b;
  --accent-2: #22c55e;
  --accent-3: #38bdf8;
  --text: #e2e8f0;
  --muted: #94a3b8;
  --shadow: 0 24px 60px rgba(3, 7, 18, 0.45);
  --glow: 0 0 24px rgba(245, 158, 11, 0.25);
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-height: 100vh;
  font-family: "Space Mono", "Fira Code", "Menlo", monospace;
  color: var(--text);
  background: radial-gradient(circle at top, #1c2540 0%, #0b0f1a 55%, #05070c 100%);
}

body::before {
  content: "";
  position: fixed;
  inset: 0;
  background: linear-gradient(120deg, rgba(56, 189, 248, 0.08), transparent 35%),
    radial-gradient(circle at 20% 20%, rgba(34, 197, 94, 0.12), transparent 40%),
    radial-gradient(circle at 80% 10%, rgba(245, 158, 11, 0.12), transparent 45%);
  pointer-events: none;
  z-index: -1;
}

#root {
  min-height: 100vh;
}

.app {
  padding: 56px clamp(16px, 4vw, 48px) 96px;
  max-width: 1200px;
  margin: 0 auto;
}

.hero {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
  flex-wrap: wrap;
  margin-bottom: 40px;
}

.eyebrow {
  text-transform: uppercase;
  letter-spacing: 0.2em;
  font-size: 12px;
  color: var(--accent-3);
  margin: 0 0 12px;
}

.hero h1 {
  margin: 0;
  font-size: clamp(32px, 4vw, 52px);
  letter-spacing: 0.06em;
}

.subtitle {
  margin-top: 12px;
  max-width: 520px;
  color: var(--muted);
  line-height: 1.6;
}

.hero-meta {
  display: grid;
  gap: 12px;
  padding: 16px 20px;
  background: var(--panel);
  border-radius: 16px;
  border: 1px solid var(--card-border);
  box-shadow: var(--shadow);
  min-width: 220px;
}

.hero-meta div {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  font-size: 13px;
}

.meta-label {
  color: var(--muted);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 20px;
}

.card {
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 20px;
  background: var(--card);
  border-radius: 18px;
  border: 1px solid var(--card-border);
  text-align: left;
  color: inherit;
  cursor: pointer;
  box-shadow: var(--shadow);
  transition: transform 0.2s ease, border-color 0.2s ease;
}

.card:hover {
  transform: translateY(-4px);
  border-color: rgba(245, 158, 11, 0.4);
}

.card-head {
  display: flex;
  justify-content: space-between;
  gap: 16px;
}

.card h3 {
  margin: 0 0 4px;
  font-size: 18px;
}

.card p {
  margin: 0;
  color: var(--muted);
  font-size: 13px;
  line-height: 1.4;
}

.badge {
  font-size: 11px;
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid rgba(56, 189, 248, 0.5);
  color: var(--accent-3);
}

.preview {
  margin: 0;
  padding: 12px;
  background: rgba(15, 23, 42, 0.8);
  border-radius: 12px;
  border: 1px solid rgba(148, 163, 184, 0.2);
  max-height: 190px;
  overflow: hidden;
  font-size: 11px;
  line-height: 1.45;
  color: #cbd5f5;
}

.card-foot {
  display: flex;
  justify-content: space-between;
  color: var(--muted);
  font-size: 12px;
}

.empty {
  grid-column: 1 / -1;
  padding: 40px;
  background: rgba(15, 23, 42, 0.8);
  border-radius: 20px;
  border: 1px dashed rgba(148, 163, 184, 0.3);
  text-align: center;
}

.empty h2 {
  margin: 0 0 12px;
}

.mono {
  font-family: inherit;
  color: var(--accent);
}

.overlay {
  position: fixed;
  inset: 0;
  background: rgba(2, 6, 23, 0.8);
  backdrop-filter: blur(12px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  z-index: 20;
}

.panel {
  width: min(1100px, 96vw);
  max-height: 90vh;
  overflow: hidden;
  background: var(--panel);
  border-radius: 24px;
  border: 1px solid rgba(148, 163, 184, 0.25);
  box-shadow: var(--shadow);
  display: flex;
  flex-direction: column;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 24px 28px 16px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.15);
}

.panel-header h2 {
  margin: 0 0 6px;
}

.panel-header p {
  margin: 0;
  color: var(--muted);
}

.ghost {
  background: transparent;
  border: 1px solid rgba(148, 163, 184, 0.4);
  color: var(--text);
  padding: 8px 14px;
  border-radius: 999px;
  cursor: pointer;
}

.panel-controls {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 28px;
  gap: 16px;
  flex-wrap: wrap;
}

.toggle-group {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.toggle-group button {
  border: 1px solid rgba(148, 163, 184, 0.4);
  background: rgba(15, 23, 42, 0.6);
  color: var(--muted);
  padding: 6px 12px;
  border-radius: 999px;
  cursor: pointer;
  font-size: 12px;
  letter-spacing: 0.08em;
}

.toggle-group button.active {
  background: rgba(245, 158, 11, 0.2);
  color: var(--text);
  border-color: rgba(245, 158, 11, 0.6);
  box-shadow: var(--glow);
}

.toggle {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: var(--muted);
}

.version-controls {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 0 28px 16px;
  font-size: 12px;
  color: var(--muted);
}

.version-controls input[type="range"] {
  flex: 1;
}

.panel-content {
  padding: 0 28px 28px;
  overflow-y: auto;
}

.surface-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 16px;
}

.surface {
  padding: 12px;
  border-radius: 16px;
  border: 1px solid rgba(148, 163, 184, 0.2);
  background: rgba(2, 6, 23, 0.6);
  position: relative;
}

.surface-label {
  position: absolute;
  top: -10px;
  right: 16px;
  background: rgba(15, 23, 42, 0.9);
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 10px;
  letter-spacing: 0.12em;
  color: var(--muted);
}

.surface pre {
  margin: 0;
  font-size: 12px;
  line-height: 1.4;
  color: #e2e8f0;
  white-space: pre-wrap;
}

.surface.web {
  border-color: rgba(56, 189, 248, 0.4);
}

.surface.cli {
  border-color: rgba(34, 197, 94, 0.4);
  box-shadow: inset 0 0 0 1px rgba(34, 197, 94, 0.2);
}

.surface.tui {
  border-color: rgba(245, 158, 11, 0.4);
  box-shadow: inset 0 0 0 1px rgba(245, 158, 11, 0.2);
}

.compare-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
}

.compare-item {
  background: rgba(8, 15, 30, 0.65);
  padding: 12px;
  border-radius: 16px;
  border: 1px solid rgba(148, 163, 184, 0.18);
}

.compare-meta {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: var(--muted);
  margin-bottom: 10px;
}

@media (max-width: 720px) {
  .hero {
    flex-direction: column;
    align-items: flex-start;
  }

  .panel-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }

  .panel-controls {
    flex-direction: column;
    align-items: flex-start;
  }

  .version-controls {
    flex-direction: column;
    align-items: stretch;
  }
}
`;

// src/web/main.tsx
import { jsx as jsx4 } from "react/jsx-runtime";
var styleTag = document.createElement("style");
styleTag.textContent = styles;
document.head.appendChild(styleTag);
var rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Root element not found");
}
createRoot(rootElement).render(/* @__PURE__ */ jsx4(App, {}));
//# sourceMappingURL=main.js.map