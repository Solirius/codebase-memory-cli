import { afterEach, describe, expect, it, vi } from "vitest";
import { ViewError, getProjects, getSchema, getSnippet } from "./views";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("views API client", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("GETs /api/projects with limit and offset", async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ projects: [], has_more: false }));
    vi.stubGlobal("fetch", fetchMock);
    const page = await getProjects(500, 0);
    expect(page).toEqual({ projects: [], has_more: false });
    expect(fetchMock).toHaveBeenCalledWith("/api/projects?limit=500&offset=0", { method: "GET" });
  });

  it("encodes every query value", async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ source: "x" }));
    vi.stubGlobal("fetch", fetchMock);
    await getSchema("a&b=c d", 10, 20);
    await getSnippet("p/q?#", "ns::fn&x=1");
    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      "/api/schema?project=a%26b%3Dc%20d&limit=10&offset=20",
      { method: "GET" },
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "/api/snippet?project=p%2Fq%3F%23&qualified_name=ns%3A%3Afn%26x%3D1",
      { method: "GET" },
    );
  });

  it("throws ViewError with status and server message when not ok", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse({ error: "missing project" }, 400)));
    const err = await getSchema("", 1, 0).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ViewError);
    expect((err as ViewError).status).toBe(400);
    expect((err as ViewError).message).toBe("missing project");
  });

  it("falls back to the HTTP status text when the error body is not JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("boom", { status: 500, statusText: "Internal Server Error" })),
    );
    const err = await getProjects(1, 0).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ViewError);
    expect((err as ViewError).status).toBe(500);
    expect((err as ViewError).message).toContain("500");
  });
});
