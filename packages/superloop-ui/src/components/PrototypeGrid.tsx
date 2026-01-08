import { motion } from "framer-motion";

import type { RenderedPrototypeView } from "../web/types.js";

type PrototypeGridProps = {
  views: RenderedPrototypeView[];
  onOpen: (view: RenderedPrototypeView) => void;
};

export function PrototypeGrid({ views, onOpen }: PrototypeGridProps) {
  return (
    <section className="grid">
      {views.length === 0 && (
        <div className="empty">
          <h2>No prototypes yet</h2>
          <p>
            Run <span className="mono">superloop-ui generate &lt;view&gt;</span> to seed
            your first ASCII mockup.
          </p>
        </div>
      )}

      {views.map((view) => (
        <motion.button
          key={view.name}
          className="card"
          layout
          initial={{ opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.35 }}
          onClick={() => onOpen(view)}
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
