import { describe, it, expect, vi } from "vitest";
import React from "react";
import { renderHook, act } from "@testing-library/react";
import { DataProvider, useData, useDataValue, useDataBinding } from "./data";

describe("DataProvider", () => {
  it("provides initial data to children", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{ user: { name: "John" } }}>
        {children}
      </DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    expect(result.current.data).toEqual({ user: { name: "John" } });
  });

  it("provides empty object when no initial data", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider>{children}</DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    expect(result.current.data).toEqual({});
  });

  it("provides auth state to children", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider authState={{ isSignedIn: true, user: { id: "123" } }}>
        {children}
      </DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    expect(result.current.authState).toEqual({
      isSignedIn: true,
      user: { id: "123" },
    });
  });
});

describe("useData", () => {
  it("provides get function to retrieve values", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{ user: { name: "John" } }}>
        {children}
      </DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    expect(result.current.get("/user/name")).toBe("John");
  });

  it("allows setting data at path with set function", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{}}>{children}</DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    act(() => {
      result.current.set("/user/name", "Alice");
    });

    expect((result.current.data.user as Record<string, unknown>).name).toBe(
      "Alice",
    );
  });

  it("calls onDataChange callback when data changes", () => {
    const onDataChange = vi.fn();
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{}} onDataChange={onDataChange}>
        {children}
      </DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    act(() => {
      result.current.set("/count", 42);
    });

    expect(onDataChange).toHaveBeenCalledWith("/count", 42);
  });

  it("allows updating multiple values with update function", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{}}>{children}</DataProvider>
    );

    const { result } = renderHook(() => useData(), { wrapper });

    act(() => {
      result.current.update({
        "/name": "John",
        "/age": 30,
      });
    });

    expect(result.current.data.name).toBe("John");
    expect(result.current.data.age).toBe(30);
  });
});

describe("useDataValue", () => {
  it("returns value at specified path", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{ user: { name: "John", age: 30 } }}>
        {children}
      </DataProvider>
    );

    const { result } = renderHook(() => useDataValue("/user/name"), {
      wrapper,
    });

    expect(result.current).toBe("John");
  });

  it("returns undefined for missing path", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{}}>{children}</DataProvider>
    );

    const { result } = renderHook(() => useDataValue("/missing"), { wrapper });

    expect(result.current).toBeUndefined();
  });

  it("updates when data changes", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{ count: 0 }}>{children}</DataProvider>
    );

    // Use a single hook that returns both values
    const { result, rerender } = renderHook(
      () => ({
        data: useData(),
        value: useDataValue<number>("/count"),
      }),
      { wrapper },
    );

    expect(result.current.value).toBe(0);

    act(() => {
      result.current.data.set("/count", 5);
    });

    rerender();
    expect(result.current.value).toBe(5);
  });
});

describe("useDataBinding", () => {
  it("returns tuple with value and setter for path", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{ name: "John" }}>{children}</DataProvider>
    );

    const { result } = renderHook(() => useDataBinding("/name"), { wrapper });

    const [value, setValue] = result.current;
    expect(value).toBe("John");
    expect(typeof setValue).toBe("function");
  });

  it("setter updates the value", () => {
    const wrapper = ({ children }: { children: React.ReactNode }) => (
      <DataProvider initialData={{ name: "John" }}>{children}</DataProvider>
    );

    const { result, rerender } = renderHook(() => useDataBinding("/name"), {
      wrapper,
    });

    act(() => {
      const [, setValue] = result.current;
      setValue("Alice");
    });

    rerender();
    const [value] = result.current;
    expect(value).toBe("Alice");
  });
});
