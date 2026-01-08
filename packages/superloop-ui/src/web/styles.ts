export const styles = `:root {
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
  position: relative;
  text-shadow: 0 0 10px rgba(56, 189, 248, 0.12);
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

.version-timeline {
  display: flex;
  gap: 8px;
  padding: 0 28px 16px;
  overflow-x: auto;
}

.version-chip {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.3);
  background: rgba(15, 23, 42, 0.7);
  color: var(--muted);
  font-size: 11px;
  cursor: pointer;
  flex-shrink: 0;
}

.version-chip span:first-child {
  color: var(--accent-3);
  font-weight: 600;
  letter-spacing: 0.08em;
}

.version-chip.active {
  color: var(--text);
  border-color: rgba(56, 189, 248, 0.7);
  box-shadow: var(--glow);
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
  overflow: auto;
}

.surface::after {
  content: "";
  position: absolute;
  inset: 0;
  background: repeating-linear-gradient(
    180deg,
    rgba(148, 163, 184, 0.08),
    rgba(148, 163, 184, 0.08) 1px,
    transparent 1px,
    transparent 3px
  );
  opacity: 0.18;
  pointer-events: none;
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
  white-space: pre;
  position: relative;
  z-index: 1;
  text-shadow: 0 0 12px rgba(56, 189, 248, 0.18);
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
