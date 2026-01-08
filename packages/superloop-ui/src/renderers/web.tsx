import { buildFrame, frameToText } from "./frame.js";

export type RendererMode = "web" | "cli" | "tui" | "all";

export function RenderSurface({
  content,
  mode,
  title,
}: {
  content: string;
  mode: RendererMode;
  title?: string;
}) {
  const framed = frameToText(buildFrame(content, title));
  const resolveContent = (surface: RendererMode) => (surface === "web" ? content : framed);

  if (mode === "all") {
    return (
      <div className="surface-grid">
        <SurfaceBlock label="Web" className="web" content={resolveContent("web")} />
        <SurfaceBlock label="CLI" className="cli" content={resolveContent("cli")} />
        <SurfaceBlock label="TUI" className="tui" content={resolveContent("tui")} />
      </div>
    );
  }

  return (
    <SurfaceBlock label={mode.toUpperCase()} className={mode} content={resolveContent(mode)} />
  );
}

export function SurfaceBlock({
  label,
  content,
  className,
}: {
  label: string;
  content: string;
  className: string;
}) {
  return (
    <div className={`surface ${className}`}>
      <div className="surface-label">{label}</div>
      <pre>{content}</pre>
    </div>
  );
}
