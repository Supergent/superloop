/**
 * Liquid Dashboard Entry Point
 *
 * Client-side entry for the superloop liquid interfaces.
 */

import { createRoot } from "react-dom/client";

import { Dashboard } from "../liquid/Dashboard.js";
import type { SuperloopContext } from "../liquid/views/types.js";

// API endpoint for context
const CONTEXT_API = "/api/liquid/context";
const OVERRIDE_API = "/api/liquid/override";

// Load context from server
async function loadContext(): Promise<SuperloopContext> {
  const response = await fetch(CONTEXT_API);
  if (!response.ok) {
    throw new Error(`Failed to load context: ${response.statusText}`);
  }
  return response.json();
}

// Load override tree from server
async function loadOverrideTree() {
  const response = await fetch(OVERRIDE_API);
  if (!response.ok || response.status === 204) {
    return null;
  }
  return response.json();
}

// Action handler - calls back to server for things like approve/cancel
async function handleAction(action: { name: string; params?: Record<string, unknown> }) {
  console.log("Action:", action);

  // For now, just log actions
  // In the future, these would call superloop CLI commands via the server
  switch (action.name) {
    case "approve_loop":
      alert("Approve action - would run: superloop approve");
      break;
    case "reject_loop":
      alert("Reject action - would run: superloop approve --reject");
      break;
    case "cancel_loop":
      alert("Cancel action - would run: superloop cancel");
      break;
    case "view_logs":
      alert("View logs action - would open log viewer");
      break;
    case "view_artifact":
      alert(`View artifact: ${action.params?.path ?? "unknown"}`);
      break;
    default:
      console.log("Unknown action:", action);
  }
}

// Render
const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Root element not found");
}

createRoot(rootElement).render(
  <Dashboard
    loadContext={loadContext}
    loadOverrideTree={loadOverrideTree}
    pollInterval={2000}
    onAction={handleAction}
  />,
);
