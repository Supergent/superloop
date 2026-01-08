export function normalizeViewName(name: string): string {
  return name.trim().replace(/[^a-zA-Z0-9_-]/g, "-");
}
