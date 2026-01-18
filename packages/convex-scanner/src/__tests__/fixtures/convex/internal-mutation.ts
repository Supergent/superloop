import { internalMutation, type MutationCtx } from './_generated/server';
import { v } from 'convex/values';

export const internalCreate = internalMutation({
  args: {
    name: v.string(),
  },
  handler: async (ctx: MutationCtx, args: { name: string }) => {
    const id = await ctx.db.insert('items', { name: args.name });
    return id;
  },
});
