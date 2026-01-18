import { mutation, type MutationCtx } from './_generated/server';
import { v } from 'convex/values';

// @convex-scanner allow-unauthenticated
export const signup = mutation({
  args: {
    email: v.string(),
  },
  handler: async (_ctx: MutationCtx, _args: { email: string }) => {
    return { ok: true };
  },
});
