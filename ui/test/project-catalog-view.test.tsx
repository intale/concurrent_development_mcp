import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { preservePageForExactScope } from "../src/projects/project-catalog-model.js";
import { ProjectCatalogView } from "../src/projects/project-catalog-view.js";
import type { ProjectCatalogViewProps } from "../src/projects/project-catalog-view.js";

const project = {
  id: "018f0f4d-4e45-7abc-8def-000000000011",
  name: "Catalog",
  paths: "/workspace/catalog",
  registeredAt: "2026-08-31T10:00:00.000000Z",
  remotes: "https://example.test/catalog.git",
  scope: "project:catalog"
} as const;

const defaults: ProjectCatalogViewProps = {
  canGoBack: false,
  errorMessage: null,
  hasNextPage: false,
  loading: false,
  onNext: () => undefined,
  onPrevious: () => undefined,
  onRetry: () => undefined,
  refreshing: false,
  rows: [],
  scopeRequired: false,
  showingPreviousData: false
};

function render(overrides: Partial<ProjectCatalogViewProps>) {
  return renderToStaticMarkup(
    <MemoryRouter><ProjectCatalogView {...defaults} {...overrides} /></MemoryRouter>
  );
}

test("renders scope, loading, empty, and retryable error states", () => {
  assert.match(render({ scopeRequired: true }), /Enter an exact project scope/);
  assert.match(render({ loading: true }), /Loading projects/);
  assert.match(render({}), /No projects are currently available/);
  const error = render({ errorMessage: "Network unavailable" });
  assert.match(error, /Network unavailable/);
  assert.match(error, /Retry/);
});

test("keeps project rows visible during a stale-preserving refresh", () => {
  const refreshing = render({
    refreshing: true,
    rows: [project],
    showingPreviousData: true
  });

  assert.match(refreshing, /last available project page remains visible/);
  assert.match(refreshing, /Showing 1 project/);
  assert.match(refreshing, /aria-label="Projects"/);
  assert.match(refreshing, />Delivery<\/a>/);
});

test("keeps project rows visible when a background refresh fails", () => {
  const failedRefresh = render({
    errorMessage: "GraphQL request failed",
    rows: [project]
  });

  assert.match(failedRefresh, /last available projects remain visible/);
  assert.match(failedRefresh, /Showing 1 project/);
  assert.match(failedRefresh, /Retry refresh/);
});

test("preserves an available page only within the same exact scope", () => {
  const page = { projects: [project] } as const;

  assert.equal(
    preservePageForExactScope(page, ["projects", "project:catalog", null], "project:catalog"),
    page
  );
  assert.equal(
    preservePageForExactScope(page, ["projects", "project:other", null], "project:catalog"),
    undefined
  );
});
