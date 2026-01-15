import { describe, it, expect, vi } from "vitest";
import { render, fireEvent, waitFor } from "@testing-library/react";
import {
  ActionProvider,
  useActions,
  useAction,
  ConfirmDialog,
} from "../actions";
import { DataProvider } from "../data";
import type { Action } from "@json-render/core";

// Test component to access the hook
function TestActions({ testAction }: { testAction?: Action }) {
  const { handlers, loadingActions, pendingConfirmation, execute, confirm, cancel, registerHandler } =
    useActions();

  const handleExecute = () => {
    execute(testAction || { name: "test" }).catch(() => {
      // Catch rejections from cancelled actions
    });
  };

  return (
    <div>
      <div data-testid="handlers-count">{Object.keys(handlers).length}</div>
      <div data-testid="loading-count">{loadingActions.size}</div>
      <div data-testid="has-pending">
        {pendingConfirmation ? "true" : "false"}
      </div>
      <button onClick={handleExecute}>
        Execute
      </button>
      <button onClick={confirm}>Confirm</button>
      <button onClick={cancel}>Cancel</button>
      <button onClick={() => registerHandler("dynamic", vi.fn())}>
        Register
      </button>
    </div>
  );
}

function TestUseAction({ action }: { action: Action }) {
  const { execute, isLoading } = useAction(action);

  return (
    <div>
      <div data-testid="is-loading">{isLoading ? "true" : "false"}</div>
      <button onClick={execute}>Execute Action</button>
    </div>
  );
}

describe("ActionProvider", () => {
  it("executes action without confirmation", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { testAction: handler };

    const { getByText } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestActions testAction={{ name: "testAction" }} />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(handler).toHaveBeenCalled();
    });
  });

  it("shows pending confirmation for actions with confirm", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { confirmAction: handler };

    const { getByText, getByTestId } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestActions
            testAction={{
              name: "confirmAction",
              confirm: {
                title: "Confirm Action",
                message: "Are you sure?",
              },
            }}
          />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(getByTestId("has-pending").textContent).toBe("true");
    });

    expect(handler).not.toHaveBeenCalled();
  });

  it("executes action after confirmation", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { confirmAction: handler };

    const { getByText } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestActions
            testAction={{
              name: "confirmAction",
              confirm: {
                title: "Confirm",
                message: "Continue?",
              },
            }}
          />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(getByText("Confirm")).toBeTruthy();
    });

    fireEvent.click(getByText("Confirm"));

    await waitFor(() => {
      expect(handler).toHaveBeenCalled();
    });
  });

  it("cancels action when cancelled", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { confirmAction: handler };

    const { getByText, getByTestId } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestActions
            testAction={{
              name: "confirmAction",
              confirm: {
                title: "Confirm",
                message: "Continue?",
              },
            }}
          />
        </ActionProvider>
      </DataProvider>,
    );

    // Execute the action (it will wait for confirmation)
    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(getByTestId("has-pending").textContent).toBe("true");
    });

    // Cancel the action (this will reject the promise, but it's handled internally)
    fireEvent.click(getByText("Cancel"));

    await waitFor(() => {
      expect(getByTestId("has-pending").textContent).toBe("false");
    });

    // Wait a bit to ensure the rejection is handled
    await new Promise((resolve) => setTimeout(resolve, 100));

    expect(handler).not.toHaveBeenCalled();
  });

  it("tracks loading state during action execution", async () => {
    let resolveHandler: () => void;
    const handlerPromise = new Promise<void>((resolve) => {
      resolveHandler = resolve;
    });

    const handler = vi.fn().mockReturnValue(handlerPromise);
    const handlers = { slowAction: handler };

    const { getByText, getByTestId } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestActions testAction={{ name: "slowAction" }} />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(getByTestId("loading-count").textContent).toBe("1");
    });

    resolveHandler!();

    await waitFor(() => {
      expect(getByTestId("loading-count").textContent).toBe("0");
    });
  });

  it("handles missing handler gracefully", async () => {
    const consoleSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    const { getByText } = render(
      <DataProvider>
        <ActionProvider>
          <TestActions testAction={{ name: "missingAction" }} />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(consoleSpy).toHaveBeenCalledWith(
        "No handler registered for action: missingAction",
      );
    });

    consoleSpy.mockRestore();
  });

  it("registers new handlers dynamically", async () => {
    const { getByText, getByTestId } = render(
      <DataProvider>
        <ActionProvider>
          <TestActions />
        </ActionProvider>
      </DataProvider>,
    );

    expect(getByTestId("handlers-count").textContent).toBe("0");

    fireEvent.click(getByText("Register"));

    await waitFor(() => {
      expect(getByTestId("handlers-count").textContent).toBe("1");
    });
  });

  it("supports navigation in action handlers", async () => {
    const navigate = vi.fn();
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { navAction: handler };

    const { getByText } = render(
      <DataProvider>
        <ActionProvider handlers={handlers} navigate={navigate}>
          <TestActions
            testAction={{
              name: "navAction",
              onSuccess: { navigate: "/success" },
            }}
          />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(navigate).toHaveBeenCalledWith("/success");
    });
  });

  it("supports data updates in action handlers", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { dataAction: handler };

    const { getByText } = render(
      <DataProvider initialData={{ count: 0 }}>
        <ActionProvider handlers={handlers}>
          <TestActions
            testAction={{
              name: "dataAction",
              onSuccess: { set: { count: 5 } },
            }}
          />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(handler).toHaveBeenCalled();
    });
  });

  it("supports chained actions via onSuccess", async () => {
    const handler1 = vi.fn().mockResolvedValue(undefined);
    const handler2 = vi.fn().mockResolvedValue(undefined);
    const handlers = { action1: handler1, action2: handler2 };

    const { getByText } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestActions
            testAction={{
              name: "action1",
              onSuccess: { action: "action2" },
            }}
          />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute"));

    await waitFor(() => {
      expect(handler1).toHaveBeenCalled();
      expect(handler2).toHaveBeenCalled();
    });
  });
});

describe("useAction hook", () => {
  it("provides execute function and loading state", () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const handlers = { testAction: handler };

    const { getByTestId } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestUseAction action={{ name: "testAction" }} />
        </ActionProvider>
      </DataProvider>,
    );

    expect(getByTestId("is-loading").textContent).toBe("false");
  });

  it("shows loading state during execution", async () => {
    let resolveHandler: () => void;
    const handlerPromise = new Promise<void>((resolve) => {
      resolveHandler = resolve;
    });

    const handler = vi.fn().mockReturnValue(handlerPromise);
    const handlers = { slowAction: handler };

    const { getByText, getByTestId } = render(
      <DataProvider>
        <ActionProvider handlers={handlers}>
          <TestUseAction action={{ name: "slowAction" }} />
        </ActionProvider>
      </DataProvider>,
    );

    fireEvent.click(getByText("Execute Action"));

    await waitFor(() => {
      expect(getByTestId("is-loading").textContent).toBe("true");
    });

    resolveHandler!();

    await waitFor(() => {
      expect(getByTestId("is-loading").textContent).toBe("false");
    });
  });
});

describe("useActions error handling", () => {
  it("throws error when used outside ActionProvider", () => {
    const TestComponent = () => {
      useActions();
      return <div>Test</div>;
    };

    expect(() => render(<TestComponent />)).toThrow(
      "useActions must be used within an ActionProvider",
    );
  });
});

describe("ConfirmDialog component", () => {
  it("renders confirmation dialog with title and message", () => {
    const onConfirm = vi.fn();
    const onCancel = vi.fn();

    const { getByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Delete Item",
          message: "Are you sure you want to delete this item?",
        }}
        onConfirm={onConfirm}
        onCancel={onCancel}
      />,
    );

    expect(getByText("Delete Item")).toBeTruthy();
    expect(getByText("Are you sure you want to delete this item?")).toBeTruthy();
  });

  it("calls onConfirm when confirm button clicked", () => {
    const onConfirm = vi.fn();
    const onCancel = vi.fn();

    const { getAllByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Confirm",
          message: "Proceed?",
        }}
        onConfirm={onConfirm}
        onCancel={onCancel}
      />,
    );

    const buttons = getAllByText("Confirm");
    fireEvent.click(buttons[1]); // Second "Confirm" is the button

    expect(onConfirm).toHaveBeenCalled();
    expect(onCancel).not.toHaveBeenCalled();
  });

  it("calls onCancel when cancel button clicked", () => {
    const onConfirm = vi.fn();
    const onCancel = vi.fn();

    const { getByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Confirm",
          message: "Proceed?",
        }}
        onConfirm={onConfirm}
        onCancel={onCancel}
      />,
    );

    fireEvent.click(getByText("Cancel"));

    expect(onCancel).toHaveBeenCalled();
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it("uses custom button labels", () => {
    const { getByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Delete",
          message: "Delete this?",
          confirmLabel: "Delete Forever",
          cancelLabel: "Keep It",
        }}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
      />,
    );

    expect(getByText("Delete Forever")).toBeTruthy();
    expect(getByText("Keep It")).toBeTruthy();
  });

  it("applies danger variant styling", () => {
    const { getByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Danger",
          message: "This is dangerous",
          variant: "danger",
        }}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
      />,
    );

    const confirmButton = getByText("Confirm");
    expect(confirmButton.style.backgroundColor).toBe("rgb(220, 38, 38)");
  });

  it("applies default variant styling", () => {
    const { getAllByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Confirm",
          message: "Proceed?",
          variant: "default",
        }}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
      />,
    );

    const buttons = getAllByText("Confirm");
    const confirmButton = buttons[1]; // Second "Confirm" is the button
    expect(confirmButton.style.backgroundColor).toBe("rgb(59, 130, 246)");
  });

  it("calls onCancel when backdrop is clicked", () => {
    const onCancel = vi.fn();

    const { container } = render(
      <ConfirmDialog
        confirm={{
          title: "Test",
          message: "Test message",
        }}
        onConfirm={vi.fn()}
        onCancel={onCancel}
      />,
    );

    const backdrop = container.firstChild as HTMLElement;
    fireEvent.click(backdrop);

    expect(onCancel).toHaveBeenCalled();
  });

  it("does not call onCancel when dialog content is clicked", () => {
    const onCancel = vi.fn();

    const { getByText } = render(
      <ConfirmDialog
        confirm={{
          title: "Test",
          message: "Test message",
        }}
        onConfirm={vi.fn()}
        onCancel={onCancel}
      />,
    );

    // Click on the title (inside dialog content)
    fireEvent.click(getByText("Test"));

    expect(onCancel).not.toHaveBeenCalled();
  });
});
