import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import {
  nextProjectPageParameters,
  parseProjectSort,
  preservePageForCatalogFilters,
  previousProjectPageParameters
} from "../src/projects/project-catalog-model.js";
import { ProjectCatalogView } from "../src/projects/project-catalog-view.js";
import type { ProjectCatalogViewProps } from "../src/projects/project-catalog-view.js";

const project = {
  projectRef: "eyJzY2hlbWEiOiJwcm9qZWN0LXJlZmVyZW5jZS92MSIsInNjb3BlIjoicHJvamVjdDpjYXRhbG9nIn0",
  displayLabel: "Catalog",
  repositoryCount: 2,
  scope: "project:catalog",
  hasMoreRepositories: false,
  repositories: [
    {
      id: "018f0f4d-4e45-7abc-8def-000000000011",
      displayName: "Catalog API",
      paths: [ "/workspace/catalog-api" ]
    },
    {
      id: "018f0f4d-4e45-7abc-8def-000000000012",
      displayName: "Catalog UI",
      paths: [ "/workspace/catalog-ui" ]
    }
  ]
} as const;

const defaults: ProjectCatalogViewProps = {
  canGoBack: false,
  errorMessage: null,
  hasNextPage: false,
  loading: false,
  onNext: () => undefined,
  onPrevious: () => undefined,
  onRetry: () => undefined,
  pageNumber: 1,
  rows: [],
  searchApplied: false,
  showingPreviousData: false
};

function render(overrides: Partial<ProjectCatalogViewProps>) {
  return renderToStaticMarkup(
    <MemoryRouter><ProjectCatalogView {...defaults} {...overrides} /></MemoryRouter>
  );
}

test("renders loading, unrefined empty, refined empty, and retryable error states", () => {
  assert.match(render({ loading: true }), /Loading available projects/);
  assert.match(render({}), /No Project scopes are currently available/);
  assert.match(render({ searchApplied: true }), /matches this search/);
  const error = render({ errorMessage: "Network unavailable" });
  assert.match(error, /Network unavailable/);
  assert.match(error, /Retry/);
});

test("shows explicit Repository membership and one visible primary Project action", () => {
  const markup = render({ rows: [project] });

  assert.match(markup, /Catalog API/);
  assert.match(markup, /Catalog UI/);
  assert.match(markup, /2 Repositories/);
  assert.match(markup, /row row-cols-1 row-cols-xl-2/);
  assert.match(markup, /card-footer d-grid/);
  assert.match(markup, />Open project/);
  assert.doesNotMatch(markup, />Coordination<\/a>.*>Resources<\/a>/);
  assert.match(markup, new RegExp(`/projects/${project.projectRef}`));
});

test("keeps available rows visible during refresh failure without a remote detail panel", () => {
  const markup = render({
    errorMessage: "GraphQL request failed",
    rows: [project]
  });

  assert.match(markup, /last available Project page remains visible/);
  assert.match(markup, /Retry refresh/);
  assert.match(markup, /aria-live="polite"/);
  assert.doesNotMatch(markup, />Refreshing/);
  assert.match(render({ rows: [project], showingPreviousData: true }), /Loading the requested page/);
});

test("binds placeholder preservation and URL cursor history to catalog filters", () => {
  const page = { projects: [project] } as const;
  assert.equal(
    preservePageForCatalogFilters(page, ["projects", "catalog", "SCOPE_ASC", null], "catalog", "SCOPE_ASC"),
    page
  );
  assert.equal(
    preservePageForCatalogFilters(page, ["projects", "other", "SCOPE_ASC", null], "catalog", "SCOPE_ASC"),
    undefined
  );
  assert.equal(parseProjectSort("unexpected"), "SCOPE_ASC");

  const first = new URLSearchParams("q=catalog");
  const second = nextProjectPageParameters(first, "cursor-1");
  const third = nextProjectPageParameters(second, "cursor-2");
  assert.equal(third.get("after"), "cursor-2");
  assert.deepEqual(third.getAll("trail"), ["", "cursor-1"]);
  assert.equal(previousProjectPageParameters(third).get("after"), "cursor-1");
  assert.equal(previousProjectPageParameters(second).has("after"), false);
});
