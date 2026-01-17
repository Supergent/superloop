/**
 * Convex Client Setup for Valet MVP
 *
 * This module provides a configured Convex client for connecting to the backend.
 */

import { ConvexReactClient } from "convex/react";

/**
 * Convex deployment URL
 *
 * In production, this should be set via environment variable.
 * For development, use the local dev server URL.
 */
const CONVEX_URL = import.meta.env.VITE_CONVEX_URL || "";

if (!CONVEX_URL) {
  console.warn(
    "VITE_CONVEX_URL not set. Convex features will be unavailable. " +
    "Set VITE_CONVEX_URL in your .env file to enable backend integration."
  );
}

/**
 * Convex client instance
 *
 * This client is used to make queries and mutations to the Convex backend.
 */
export const convexClient = new ConvexReactClient(CONVEX_URL);

/**
 * Helper to check if Convex is configured
 */
export function isConvexConfigured(): boolean {
  return !!CONVEX_URL;
}
