import { query, type QueryCtx } from './_generated/server';

export const myQuery = query({
  args: {},
  handler: async (ctx: QueryCtx) => {
    const identity = await ctx.auth.getUserIdentity();
    return { user: identity };
  },
});
