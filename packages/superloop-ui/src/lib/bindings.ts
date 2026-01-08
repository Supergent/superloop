export type BindingRecord = Record<string, unknown>;

export function injectBindings(template: string, data: BindingRecord): string {
  return template.replace(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g, (match, key) => {
    const value = resolvePath(data, key);
    if (value === undefined || value === null) {
      return match;
    }
    if (typeof value === "object") {
      return JSON.stringify(value);
    }
    return String(value);
  });
}

function resolvePath(data: BindingRecord, key: string): unknown {
  if (!key.includes(".")) {
    return data[key];
  }
  return key.split(".").reduce<unknown>((acc, segment) => {
    if (acc && typeof acc === "object" && segment in (acc as Record<string, unknown>)) {
      return (acc as Record<string, unknown>)[segment];
    }
    return undefined;
  }, data);
}
