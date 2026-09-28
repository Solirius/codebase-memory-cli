/* @vitest-environment jsdom */
import { renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useProjects } from "./useProjects";

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

describe("useProjects machine-readable pagination", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => vi.unstubAllGlobals());

  it("GETs every project and schema page and merges them", async () => {
    fetchMock.mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.method).toBe("GET");
      const url = new URL(String(input), "http://127.0.0.1");
      const offset = url.searchParams.get("offset");
      if (url.pathname === "/api/projects") {
        if (offset === "0") {
          return jsonResponse({
            projects: [{ name: "alpha", root_path: "/alpha", indexed_at: "now" }],
            has_more: true,
            next_offset: 1,
          });
        }
        return jsonResponse({
          projects: [{ name: "beta", root_path: "/beta", indexed_at: "now" }],
          has_more: false,
        });
      }
      if (url.pathname === "/api/schema" && url.searchParams.get("project") === "alpha") {
        if (offset === "0") {
          return jsonResponse({
            node_labels: [{ label: "Function", count: 3 }],
            edge_types: [],
            total_nodes: 3,
            total_edges: 2,
            has_more: true,
            next_offset: 1,
          });
        }
        return jsonResponse({
          node_labels: [],
          edge_types: [{ type: "CALLS", count: 2 }],
          total_nodes: 3,
          total_edges: 2,
          has_more: false,
        });
      }
      return jsonResponse({
        node_labels: [{ label: "Class", count: 1 }],
        edge_types: [],
        total_nodes: 1,
        total_edges: 0,
        has_more: false,
      });
    });

    const { result } = renderHook(() => useProjects());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.error).toBeNull();
    expect(result.current.projects).toHaveLength(2);
    expect(result.current.projects[0].schema?.node_labels).toEqual([
      { label: "Function", count: 3 },
    ]);
    expect(result.current.projects[0].schema?.edge_types).toEqual([
      { type: "CALLS", count: 2 },
    ]);
    const urls = fetchMock.mock.calls.map((call) => String(call[0]));
    expect(urls).toContain("/api/projects?limit=500&offset=0");
    expect(urls).toContain("/api/projects?limit=500&offset=1");
    expect(urls).toContain("/api/schema?project=alpha&limit=500&offset=0");
    expect(urls).toContain("/api/schema?project=alpha&limit=500&offset=1");
    expect(urls.every((u) => u.startsWith("/api/"))).toBe(true);
  });
});
