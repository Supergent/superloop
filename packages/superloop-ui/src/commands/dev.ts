import { startDevServer } from "../server/dev.js";

export async function devCommand(params: {
  repoRoot: string;
  loopId?: string;
  port: number;
  host: string;
  open: boolean;
}): Promise<void> {
  await startDevServer({
    repoRoot: params.repoRoot,
    loopId: params.loopId,
    port: params.port,
    host: params.host,
    open: params.open,
  });
}
