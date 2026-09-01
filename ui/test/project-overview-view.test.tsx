import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { ProjectOverviewView } from "../src/projects/project-overview-view.js";
import type { ProjectOverviewViewProps } from "../src/projects/project-overview-view.js";

const repository = {
  id: "018f0f4d-4e45-7abc-8def-000000000031",
  displayName: "Coordinator",
  paths: [ "/workspace/coordinator" ],
  registeredAt: "2026-09-01T10:00:00.000000Z",
  remotes: [ "https://example.test/coordinator.git" ]
} as const;

const defaults: ProjectOverviewViewProps = {
  canGoBack: false,
  errorMessage: null,
  hasNextPage: false,
  loading: false,
  onNext: () => undefined,
  onPrevious: () => undefined,
  onRetry: () => undefined,
  pageNumber: 1,
  projectRef: "opaque-project-reference",
  refreshing: false,
  repositories: [repository],
  repositoryCount: 1
};

function render(overrides: Partial<ProjectOverviewViewProps>) {
  return renderToStaticMarkup(
    <MemoryRouter><ProjectOverviewView {...defaults} {...overrides} /></MemoryRouter>
  );
}

test("renders useful summary actions and Repository details in the overview", () => {
  const markup = render({});

  assert.match(markup, /1<\/h3>/);
  assert.match(markup, /Open coordination/);
  assert.match(markup, /Inspect resources/);
  assert.match(markup, /Coordinator/);
  assert.match(markup, /\/workspace\/coordinator/);
  assert.match(markup, /Repository ID/);
});

test("renders bounded contextual loading, failure, and available-data refresh states", () => {
  assert.match(render({ loading: true, repositories: [] }), /Loading Project overview/);
  assert.match(
    render({ errorMessage: "Network unavailable", repositories: [] }),
    /Project overview could not be loaded/
  );
  const available = render({ errorMessage: "Refresh failed", repositories: [repository] });
  assert.match(available, /last available Repository page remains visible/);
  assert.match(available, /Coordinator/);
});

test("keeps member paging controls explicit and adjacent to the member collection", () => {
  const markup = render({ canGoBack: true, hasNextPage: true, pageNumber: 2 });

  assert.match(markup, /Repository member pagination/);
  assert.match(markup, /Page 2/);
  assert.doesNotMatch(markup, /Previous page" disabled/);
  assert.doesNotMatch(markup, /Next page" disabled/);
});
