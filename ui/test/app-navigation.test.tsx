import assert from "node:assert/strict";
import test from "node:test";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { App } from "../src/app.js";
import { PROJECT_REPOSITORY_PREVIEW_SIZE, projectWorkspaceQueryKey } from "../src/projects/project-catalog-api.js";

function renderApp(path: string, queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } }
})) {
  return renderToStaticMarkup(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>
  );
}

test("renders a discoverable accessible application shell without requiring an exact scope", () => {
  const markup = renderApp("/projects");

  assert.match(markup, /Skip to main content/);
  assert.match(markup, /aria-controls="primary-sidebar"/);
  assert.match(markup, /aria-label="Primary navigation"/);
  assert.match(markup, /aria-label="Close navigation"/);
  assert.match(markup, /id="main-content"/);
  assert.match(markup, /Latest available projections/);
  assert.match(markup, /<h1[^>]*>Projects<\/h1>/);
  assert.match(markup, /Scope, Repository name, or path/);
  assert.doesNotMatch(markup, /Exact project scope/);
});

test("renders Project identity and persistent section navigation from an opaque Project route", () => {
  const projectRef = "opaque-project-reference";
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  queryClient.setQueryData(
    projectWorkspaceQueryKey(projectRef, PROJECT_REPOSITORY_PREVIEW_SIZE, null),
    {
      project: {
        projectRef,
        displayLabel: "Concurrent Development MCP",
        repositoryCount: 2,
        scope: "project:concurrent_development_mcp",
        repositories: {
          nodes: [
            {
              id: "018f0f4d-4e45-7abc-8def-000000000021",
              displayName: "Coordinator",
              paths: [ "/workspace/coordinator" ],
              registeredAt: "2026-09-01T10:00:00.000000Z",
              remotes: []
            }
          ],
          totalCount: 2,
          pageInfo: { endCursor: "repository-cursor", hasNextPage: true }
        }
      }
    }
  );

  const markup = renderApp(`/projects/${projectRef}`, queryClient);

  assert.match(markup, /Concurrent Development MCP/);
  assert.match(markup, /project:concurrent_development_mcp/);
  assert.match(markup, /2 Repositories/);
  assert.match(markup, /aria-label="Project sections"/);
  for (const section of ["Overview", "Coordination", "Resources", "Knowledge", "Governance", "Delivery"]) {
    assert.match(markup, new RegExp(`>${section}<`));
  }
  assert.match(markup, /aria-current="page"[^>]*>Overview/);
});
