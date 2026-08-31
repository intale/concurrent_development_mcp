import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type { ProjectCoordinationQuery } from "../src/gql/graphql.js";
import { preserveDashboardForProject } from "../src/coordination/project-coordination-model.js";
import { ProjectCoordinationView } from "../src/coordination/project-coordination-view.js";

const timestamp = "2026-08-31T12:00:00.000000Z";
const dashboard = {
  project: { id: "018f0f4d-4e45-7abc-8def-000000000041", name: "Dashboard", scope: "project:dashboard" },
  changeSets: {
    nodes: [{
      id: "CS-dashboard",
      goal: "Coordinate two agents",
      acceptanceCriteria: ["Both agents remain attributable"],
      domainStatus: "active",
      workItemCount: 2,
      runningWorkItemCount: 2,
      openWorkItemCount: 0,
      lastProcessedAt: timestamp
    }],
    pageInfo: { endCursor: "next-change-set", hasNextPage: true }
  },
  workItems: {
    nodes: ["luna-one", "luna-two"].map((agent, index) => ({
      id: `W-running-${index + 1}`,
      changeSetId: "CS-dashboard",
      repositoryId: "018f0f4d-4e45-7abc-8def-000000000041",
      goal: `Run lane ${index + 1}`,
      acceptanceCriteria: ["Lane is attributable"],
      competitiveMode: false,
      domainStatus: "acquired",
      presentationStatus: "RUNNING" as const,
      activeAttemptId: `A-running-${index + 1}`,
      activeAgentId: agent,
      attemptStatus: "started",
      attemptAuthorizedAt: timestamp,
      attemptStartedAt: timestamp,
      attemptTerminalAt: null,
      createdAt: timestamp,
      madeReadyAt: timestamp,
      acquiredAt: timestamp,
      completedAt: null,
      lastProcessedAt: timestamp
    })),
    pageInfo: { endCursor: "next-work-item", hasNextPage: true }
  },
  dependencies: {
    nodes: [{
      id: "D-blocking",
      producerWorkItemId: "W-running-1",
      consumerWorkItemId: "W-running-2",
      producerRepositoryId: "018f0f4d-4e45-7abc-8def-000000000041",
      consumerRepositoryId: "018f0f4d-4e45-7abc-8def-000000000041",
      dependencyKind: "requires_completion",
      blocking: true,
      declaredAt: timestamp,
      satisfiedAt: null,
      lastProcessedAt: timestamp
    }],
    pageInfo: { endCursor: "next-dependency", hasNextPage: true }
  }
} satisfies NonNullable<ProjectCoordinationQuery["projectCoordination"]>;

const callbacks = {
  onNextChangeSets: () => undefined,
  onNextDependencies: () => undefined,
  onNextWorkItems: () => undefined,
  onRetry: () => undefined
};

function render(overrides: Partial<Parameters<typeof ProjectCoordinationView>[0]> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter>
      <ProjectCoordinationView
        dashboard={dashboard}
        errorMessage={null}
        loading={false}
        refreshing={false}
        {...callbacks}
        {...overrides}
      />
    </MemoryRouter>
  );
}

test("shows concurrent running agents, attempts, blockers, and bounded-page controls", () => {
  const markup = render();

  assert.match(markup, /luna-one/);
  assert.match(markup, /luna-two/);
  assert.match(markup, /A-running-1/);
  assert.match(markup, /A-running-2/);
  assert.match(markup, /blocking/);
  assert.match(markup, /Next ChangeSets page/);
  assert.match(markup, /Next work-items page/);
  assert.match(markup, /Next dependencies page/);
});

test("keeps the latest available dashboard visible when refresh fails", () => {
  const markup = render({ errorMessage: "Projection endpoint unavailable", refreshing: true });

  assert.match(markup, /last available dashboard remains visible/);
  assert.match(markup, /Projection endpoint unavailable/);
  assert.match(markup, /Refreshing latest available coordination facts/);
  assert.match(markup, /luna-one/);
});

test("renders loading, unavailable, and retryable initial errors", () => {
  assert.match(render({ dashboard: null, loading: true }), /Loading coordination dashboard/);
  assert.match(render({ dashboard: null }), /not available in the latest projection/);
  assert.match(render({ dashboard: null, errorMessage: "Network unavailable" }), /Retry/);
});

test("preserves prior data only for the same project", () => {
  const page: ProjectCoordinationQuery = { projectCoordination: dashboard };

  assert.equal(
    preserveDashboardForProject(page, ["project-coordination", dashboard.project.id], dashboard.project.id),
    page
  );
  assert.equal(
    preserveDashboardForProject(page, ["project-coordination", "another-project"], dashboard.project.id),
    undefined
  );
});
