import { describe, it, expect } from "vitest";
import React from "react";
import { renderHook } from "@testing-library/react";
import { VisibilityProvider, useVisibility, useIsVisible } from "./visibility";
import { DataProvider } from "./data";

const createWrapper =
  (data: Record<string, unknown> = {}, authState?: { isSignedIn: boolean }) =>
  ({ children }: { children: React.ReactNode }) => (
    <DataProvider initialData={data} authState={authState}>
      <VisibilityProvider>{children}</VisibilityProvider>
    </DataProvider>
  );

describe("useVisibility", () => {
  it("provides isVisible function", () => {
    const { result } = renderHook(() => useVisibility(), {
      wrapper: createWrapper(),
    });

    expect(typeof result.current.isVisible).toBe("function");
  });

  it("provides visibility context", () => {
    const { result } = renderHook(() => useVisibility(), {
      wrapper: createWrapper({ test: true }),
    });

    expect(result.current.ctx.dataModel).toEqual({ test: true });
  });
});

describe("useIsVisible", () => {
  it("returns true for undefined condition", () => {
    const { result } = renderHook(() => useIsVisible(undefined), {
      wrapper: createWrapper(),
    });

    expect(result.current).toBe(true);
  });

  it("returns true for true condition", () => {
    const { result } = renderHook(() => useIsVisible(true), {
      wrapper: createWrapper(),
    });

    expect(result.current).toBe(true);
  });

  it("returns false for false condition", () => {
    const { result } = renderHook(() => useIsVisible(false), {
      wrapper: createWrapper(),
    });

    expect(result.current).toBe(false);
  });

  it("evaluates path conditions against data", () => {
    const { result: trueResult } = renderHook(
      () => useIsVisible({ path: "/isVisible" }),
      { wrapper: createWrapper({ isVisible: true }) },
    );
    expect(trueResult.current).toBe(true);

    const { result: falseResult } = renderHook(
      () => useIsVisible({ path: "/isVisible" }),
      { wrapper: createWrapper({ isVisible: false }) },
    );
    expect(falseResult.current).toBe(false);
  });

  it("evaluates auth conditions", () => {
    const { result: signedInResult } = renderHook(
      () => useIsVisible({ auth: "signedIn" }),
      { wrapper: createWrapper({}, { isSignedIn: true }) },
    );
    expect(signedInResult.current).toBe(true);

    const { result: signedOutResult } = renderHook(
      () => useIsVisible({ auth: "signedOut" }),
      { wrapper: createWrapper({}, { isSignedIn: false }) },
    );
    expect(signedOutResult.current).toBe(true);
  });

  it("evaluates logic expressions", () => {
    const { result } = renderHook(() => useIsVisible({ eq: [1, 1] }), {
      wrapper: createWrapper(),
    });

    expect(result.current).toBe(true);
  });

  it("evaluates complex conditions with data", () => {
    const { result } = renderHook(
      () =>
        useIsVisible({
          and: [{ path: "/user/isAdmin" }, { eq: [{ path: "/count" }, 5] }],
        }),
      { wrapper: createWrapper({ user: { isAdmin: true }, count: 5 }) },
    );

    expect(result.current).toBe(true);
  });
});
