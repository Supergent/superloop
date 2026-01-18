import { mutation, type MutationCtx } from './_generated/server';
import { v } from 'convex/values';

export const createItem = mutation({
  args: {
    name: v.string(),
  },
  handler: async (ctx: MutationCtx, args: { name: string }) => {
    const id = await ctx.db.insert('items', { name: args.name });
    return id;
  },
});
