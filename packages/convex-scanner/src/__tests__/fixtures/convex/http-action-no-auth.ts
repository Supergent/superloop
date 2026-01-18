import { httpAction } from './_generated/server';

export const httpHandler = httpAction(async (_ctx: any) => {
  return { ok: true };
});
