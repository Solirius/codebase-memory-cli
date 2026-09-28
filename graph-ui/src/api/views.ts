/* Read-only view client — GET /api/projects|schema|snippet.
   The server fixes tool arguments (format, detail, source_mode) and replies
   with the plain tool payload. */

export class ViewError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "ViewError";
  }
}

async function getView<T>(path: string, params: Record<string, string | number>): Promise<T> {
  const query = Object.entries(params)
    .map(([key, value]) => `${key}=${encodeURIComponent(String(value))}`)
    .join("&");
  const res = await fetch(`${path}?${query}`, { method: "GET" });
  if (!res.ok) {
    let message = `HTTP ${res.status}: ${res.statusText}`;
    try {
      const body = await res.json();
      if (body && typeof body.error === "string") message = body.error;
    } catch {
      /* non-JSON error body: keep the status text */
    }
    throw new ViewError(res.status, message);
  }
  return (await res.json()) as T;
}

export function getProjects<T = unknown>(limit: number, offset: number): Promise<T> {
  return getView<T>("/api/projects", { limit, offset });
}

export function getSchema<T = unknown>(project: string, limit: number, offset: number): Promise<T> {
  return getView<T>("/api/schema", { project, limit, offset });
}

export function getSnippet<T = unknown>(project: string, qualifiedName: string): Promise<T> {
  return getView<T>("/api/snippet", { project, qualified_name: qualifiedName });
}
