import { injectBindings } from "./bindings.js";
import { type PrototypeView, listPrototypes } from "./prototypes.js";
import { loadSuperloopData } from "./superloop-data.js";

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

export type PrototypesPayload = {
  views: RenderedPrototypeView[];
  loopId?: string;
  data: Record<string, string>;
  updatedAt: string;
};

export async function buildPrototypesPayload(params: {
  repoRoot: string;
  loopId?: string;
}): Promise<PrototypesPayload> {
  const [views, superloop] = await Promise.all([
    listPrototypes(params.repoRoot),
    loadSuperloopData({ repoRoot: params.repoRoot, loopId: params.loopId }),
  ]);

  const renderedViews = views.map((view) => renderView(view, superloop.data));

  return {
    views: renderedViews,
    loopId: superloop.loopId,
    data: superloop.data,
    updatedAt: new Date().toISOString(),
  };
}

function renderView(view: PrototypeView, data: Record<string, string>): RenderedPrototypeView {
  const versions = view.versions.map((version) => ({
    ...version,
    rendered: injectBindings(version.content, data),
  }));
  const latest = versions[versions.length - 1];

  return {
    name: view.name,
    description: view.description,
    versions,
    latest,
  };
}
