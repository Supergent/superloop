import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render } from "@testing-library/react";
import { useUIStream } from "../hooks";
import type { UITree } from "@json-render/core";
import { act } from "react";

// Helper component to test the hook
function TestComponent({
  api,
  onComplete,
  onError,
  autoSend,
  prompt,
}: {
  api: string;
  onComplete?: (tree: UITree) => void;
  onError?: (error: Error) => void;
  autoSend?: boolean;
  prompt?: string;
}) {
  const { tree, isStreaming, error, send, clear } = useUIStream({
    api,
    onComplete,
    onError,
  });

  // Auto send on mount if requested
  if (autoSend && prompt) {
    send(prompt);
  }

  return (
    <div>
      <div data-testid="streaming">{isStreaming ? "true" : "false"}</div>
      <div data-testid="error">{error?.message || "null"}</div>
      <div data-testid="tree">{JSON.stringify(tree)}</div>
      <button onClick={() => send("test prompt")}>Send</button>
      <button onClick={clear}>Clear</button>
    </div>
  );
}

describe("useUIStream hook", () => {
  let originalFetch: typeof global.fetch;

  beforeEach(() => {
    originalFetch = global.fetch;
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  describe("parsePatchLine and applyPatch via useUIStream", () => {
    it("applies set operation for root path", async () => {
      const mockResponse = new Response(
        JSON.stringify({ op: "set", path: "/root", value: "newRoot" }) + "\n",
        {
          headers: { "Content-Type": "application/json" },
        },
      );

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      let completedTree: UITree | null = null;
      const onComplete = vi.fn((tree: UITree) => {
        completedTree = tree;
      });

      const { getByTestId, getByText } = render(
        <TestComponent api="/api/generate" onComplete={onComplete} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(completedTree?.root).toBe("newRoot");
      expect(onComplete).toHaveBeenCalled();
    });

    it("applies add operation for new element", async () => {
      const newElement = {
        key: "text1",
        type: "text",
        props: { content: "Hello" },
      };

      const mockResponse = new Response(
        JSON.stringify({
          op: "add",
          path: "/elements/text1",
          value: newElement,
        }) + "\n",
        {
          headers: { "Content-Type": "application/json" },
        },
      );

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      let completedTree: UITree | null = null;
      const onComplete = vi.fn((tree: UITree) => {
        completedTree = tree;
      });

      const { getByText } = render(
        <TestComponent api="/api/generate" onComplete={onComplete} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(completedTree?.elements.text1).toEqual(newElement);
    });

    it("applies replace operation for element property", async () => {
      // First add an element, then replace a property
      const patches = [
        {
          op: "add",
          path: "/elements/btn",
          value: { key: "btn", type: "button", props: { label: "Old" } },
        },
        {
          op: "replace",
          path: "/elements/btn/props/label",
          value: "New",
        },
      ];

      const mockResponse = new Response(
        patches.map((p) => JSON.stringify(p)).join("\n") + "\n",
        {
          headers: { "Content-Type": "application/json" },
        },
      );

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      let completedTree: UITree | null = null;
      const onComplete = vi.fn((tree: UITree) => {
        completedTree = tree;
      });

      const { getByText } = render(
        <TestComponent api="/api/generate" onComplete={onComplete} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(completedTree?.elements.btn.props.label).toBe("New");
    });

    it("applies remove operation for element", async () => {
      const patches = [
        {
          op: "add",
          path: "/elements/elem1",
          value: { key: "elem1", type: "text", props: {} },
        },
        {
          op: "add",
          path: "/elements/elem2",
          value: { key: "elem2", type: "text", props: {} },
        },
        { op: "remove", path: "/elements/elem1" },
      ];

      const mockResponse = new Response(
        patches.map((p) => JSON.stringify(p)).join("\n") + "\n",
        {
          headers: { "Content-Type": "application/json" },
        },
      );

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      let completedTree: UITree | null = null;
      const onComplete = vi.fn((tree: UITree) => {
        completedTree = tree;
      });

      const { getByText } = render(
        <TestComponent api="/api/generate" onComplete={onComplete} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(completedTree?.elements.elem1).toBeUndefined();
      expect(completedTree?.elements.elem2).toBeDefined();
    });

    it("skips invalid JSON lines", async () => {
      const response = [
        '{ "op": "set", "path": "/root", "value": "root1" }',
        "invalid json line",
        "",
        "// comment line",
        '{ "op": "add", "path": "/elements/elem1", "value": { "key": "elem1", "type": "text", "props": {} } }',
      ].join("\n");

      const mockResponse = new Response(response, {
        headers: { "Content-Type": "application/json" },
      });

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      let completedTree: UITree | null = null;
      const onComplete = vi.fn((tree: UITree) => {
        completedTree = tree;
      });

      const { getByText } = render(
        <TestComponent api="/api/generate" onComplete={onComplete} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      // Should have processed only valid lines
      expect(completedTree?.root).toBe("root1");
      expect(completedTree?.elements.elem1).toBeDefined();
    });

    it("processes final buffer after stream ends", async () => {
      // Last patch without trailing newline
      const response =
        '{ "op": "set", "path": "/root", "value": "finalRoot" }';

      const mockResponse = new Response(response, {
        headers: { "Content-Type": "application/json" },
      });

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      let completedTree: UITree | null = null;
      const onComplete = vi.fn((tree: UITree) => {
        completedTree = tree;
      });

      const { getByText } = render(
        <TestComponent api="/api/generate" onComplete={onComplete} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(completedTree?.root).toBe("finalRoot");
    });
  });

  describe("error handling", () => {
    it("handles HTTP error responses", async () => {
      const mockResponse = new Response("Not Found", { status: 404 });
      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      const onError = vi.fn();

      const { getByText } = render(
        <TestComponent api="/api/generate" onError={onError} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(onError).toHaveBeenCalled();
      expect(onError.mock.calls[0][0].message).toContain("HTTP error: 404");
    });

    it("handles missing response body", async () => {
      const mockResponse = new Response(null, {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      const onError = vi.fn();

      const { getByText } = render(
        <TestComponent api="/api/generate" onError={onError} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(onError).toHaveBeenCalled();
      expect(onError.mock.calls[0][0].message).toContain("No response body");
    });

    it("handles network errors", async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error("Network failure"));

      const onError = vi.fn();

      const { getByText } = render(
        <TestComponent api="/api/generate" onError={onError} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(onError).toHaveBeenCalled();
      expect(onError.mock.calls[0][0].message).toBe("Network failure");
    });

    it("handles non-Error rejections", async () => {
      global.fetch = vi.fn().mockRejectedValue("String error");

      const onError = vi.fn();

      const { getByText } = render(
        <TestComponent api="/api/generate" onError={onError} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      expect(onError).toHaveBeenCalled();
      expect(onError.mock.calls[0][0].message).toBe("String error");
    });

    it("ignores AbortError when request is aborted", async () => {
      const abortError = new Error("Aborted");
      abortError.name = "AbortError";

      global.fetch = vi.fn().mockRejectedValue(abortError);

      const onError = vi.fn();

      const { getByText } = render(
        <TestComponent api="/api/generate" onError={onError} />,
      );

      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      // Should not call onError for AbortError
      expect(onError).not.toHaveBeenCalled();
    });
  });

  describe("clear functionality", () => {
    it("clears tree and error state", async () => {
      const mockResponse = new Response(
        JSON.stringify({ op: "set", path: "/root", value: "testRoot" }) + "\n",
        {
          headers: { "Content-Type": "application/json" },
        },
      );

      global.fetch = vi.fn().mockResolvedValue(mockResponse);

      const { getByText, getByTestId } = render(
        <TestComponent api="/api/generate" />,
      );

      // Send request
      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 100));
      });

      // Verify tree exists
      expect(getByTestId("tree").textContent).not.toBe("null");

      // Clear
      await act(async () => {
        getByText("Clear").click();
      });

      // Verify tree is cleared
      expect(getByTestId("tree").textContent).toBe("null");
      expect(getByTestId("error").textContent).toBe("null");
    });
  });

  describe("concurrent requests", () => {
    it("aborts previous request when new one starts", async () => {
      let firstAborted = false;
      let secondCompleted = false;

      // Mock fetch to track abort signals
      global.fetch = vi.fn((url, options) => {
        const signal = options?.signal;

        return new Promise((resolve, reject) => {
          if (signal) {
            signal.addEventListener("abort", () => {
              firstAborted = true;
              reject(new DOMException("Aborted", "AbortError"));
            });
          }

          // Simulate delay
          setTimeout(() => {
            secondCompleted = true;
            resolve(
              new Response(
                JSON.stringify({ op: "set", path: "/root", value: "root" }) +
                  "\n",
                { headers: { "Content-Type": "application/json" } },
              ),
            );
          }, 50);
        });
      });

      const { getByText } = render(<TestComponent api="/api/generate" />);

      // Start first request
      await act(async () => {
        getByText("Send").click();
      });

      // Immediately start second request (should abort first)
      await act(async () => {
        getByText("Send").click();
        await new Promise((resolve) => setTimeout(resolve, 150));
      });

      expect(firstAborted).toBe(true);
      expect(secondCompleted).toBe(true);
    });
  });
});
