import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type { ProjectResourcesQuery } from "../src/gql/graphql.js";
import { preserveResourcesForProject } from "../src/resources/project-resources-model.js";
import { ProjectResourcesView } from "../src/resources/project-resources-view.js";

const timestamp = "2026-08-31T12:00:00.000000Z";
const browser = {
  project: {
    id: "018f0f4d-4e45-7abc-8def-000000000061",
    name: "Resource browser",
    scope: "project:resource-browser"
  },
  resources: {
    nodes: [{
      id: "018f0f4d-4e45-7abc-8def-000000000062",
      repositoryId: "018f0f4d-4e45-7abc-8def-000000000061",
      kind: "FILE" as const,
      path: "app/models/leased.rb",
      lifecycleStatus: "CURRENT" as const,
      unbindingReason: null,
      registeredAt: timestamp,
      lastTransitionAt: timestamp
    }],
    pageInfo: { endCursor: "next-resource", hasNextPage: true }
  },
  activeLeases: {
    asOf: timestamp,
    nodes: [{
      id: "018f0f4d-4e45-7abc-8def-000000000064",
      leaseSetId: "018f0f4d-4e45-7abc-8def-000000000065",
      resourceId: "018f0f4d-4e45-7abc-8def-000000000062",
      resourceKind: "FILE" as const,
      resourcePath: "app/models/leased.rb",
      resourceLifecycleStatus: "CURRENT" as const,
      baseBlobOid: "b".repeat(40),
      fencingToken: "7",
      policyVersion: "coordinator-resource-lease/v2",
      changeSetId: "CS-resources",
      workItemId: "W-owner",
      attemptId: "A-owner",
      agentId: "luna-owner",
      reservedEventId: "018f0f4d-4e45-7abc-8def-000000000066",
      lastExpandedEventId: null,
      lastRenewedEventId: null,
      reservedAt: timestamp,
      lastExpandedAt: null,
      lastRenewedAt: null,
      previousExpiresAt: null,
      expiresAt: "2026-08-31T12:10:00.000000Z",
      lastProjectedAt: timestamp
    }],
    pageInfo: { endCursor: "next-lease", hasNextPage: true }
  }
} satisfies NonNullable<ProjectResourcesQuery["projectResources"]>;

const callbacks = {
  onNextActiveLeases: () => undefined,
  onNextResources: () => undefined,
  onRetry: () => undefined
};

function render(overrides: Partial<Parameters<typeof ProjectResourcesView>[0]> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter>
      <ProjectResourcesView
        browser={browser}
        errorMessage={null}
        loading={false}
        refreshing={false}
        {...callbacks}
        {...overrides}
      />
    </MemoryRouter>
  );
}

test("shows projected resources and only factual active lease ownership", () => {
  const markup = render();

  assert.match(markup, /app\/models\/leased.rb/);
  assert.match(markup, /luna-owner/);
  assert.match(markup, /A-owner/);
  assert.match(markup, /W-owner/);
  assert.match(markup, /Next resources page/);
  assert.match(markup, /Next active leases page/);
  assert.match(markup, /Ownership is derived only from projected lease facts/);
  assert.match(markup, /aria-label="Project resources"/);
  assert.match(markup, /aria-label="Active resource leases"/);
});

test("keeps the latest available resource view visible when refresh fails", () => {
  const markup = render({ errorMessage: "Projection endpoint unavailable", refreshing: true });

  assert.match(markup, /last available resource view remains visible/);
  assert.match(markup, /Projection endpoint unavailable/);
  assert.match(markup, /Refreshing latest available resource facts/);
  assert.match(markup, /luna-owner/);
});

test("renders loading, unavailable, and retryable initial errors", () => {
  assert.match(render({ browser: null, loading: true }), /Loading project resources/);
  assert.match(render({ browser: null }), /not available in the latest projection/);
  assert.match(render({ browser: null, errorMessage: "Network unavailable" }), /Retry/);
});

test("preserves prior data only for the same project", () => {
  const page: ProjectResourcesQuery = { projectResources: browser };

  assert.equal(
    preserveResourcesForProject(page, ["project-resources", browser.project.id], browser.project.id),
    page
  );
  assert.equal(
    preserveResourcesForProject(page, ["project-resources", "another-project"], browser.project.id),
    undefined
  );
});
