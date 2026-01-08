export type RendererMode = "web" | "cli" | "tui" | "all";

export function RenderSurface({ content, mode }: { content: string; mode: RendererMode }) {
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

export function SurfaceBlock({
  label,
  content,
  className
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
