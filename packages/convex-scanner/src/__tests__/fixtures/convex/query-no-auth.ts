import { query, type QueryCtx } from './_generated/server';

export const listItems = query({
  args: {},
  handler: async (ctx: QueryCtx) => {
    return await ctx.db.query('items').collect();
  },
});
