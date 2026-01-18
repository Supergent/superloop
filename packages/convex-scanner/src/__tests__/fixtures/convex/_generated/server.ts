// Fixture stub for _generated/server types
// This allows test fixtures to import from convex/_generated/server

export interface MutationCtx {
  db: any;
  auth: {
    getUserIdentity: () => Promise<{ subject: string } | null>;
  };
  storage: any;
  scheduler: any;
}

export interface QueryCtx {
  db: any;
  auth: {
    getUserIdentity: () => Promise<{ subject: string } | null>;
  };
}

export const query = (handler: any) => handler;
export const mutation = (handler: any) => handler;
export const action = (handler: any) => handler;
export const httpAction = (handler: any) => handler;
export const internalQuery = (handler: any) => handler;
export const internalMutation = (handler: any) => handler;
export const internalAction = (handler: any) => handler;
