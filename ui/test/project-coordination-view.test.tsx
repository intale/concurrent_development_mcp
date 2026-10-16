import assert from "node:assert/strict";
import test from "node:test";
import type { ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  CoordinationChangeSet,
  CoordinationDependency,
  CoordinationWorkItem,
  CoordinationWorkItemDetail
} from "../src/coordination/project-coordination-model.js";
import {
  detailLocation,
  exactWorkItemFilterParams,
  nextPageParams,
  previousPageParams,
  safeReturnTo
} from "../src/coordination/project-coordination-model.js";
import {
  ChangeSetTable,
  DependencyTable,
  PaginationControls,
  WorkItemTable,
  WorkItemDetail
} from "../src/coordination/project-coordination-view.js";

const timestamp = "2026-09-01T12:00:00.000000Z";
const changeSet = {
  id: "CS-focused",
  goal: "Keep two agents coordinated",
  acceptanceCriteria: ["Both assignments remain visible"],
  domainStatus: "active",
  workItemCount: 2,
  runningWorkItemCount: 2,
  openWorkItemCount: 2,
  lastProcessedAt: timestamp
} satisfies CoordinationChangeSet;
const workItem = {
  id: "W-luna-one",
  changeSetId: changeSet.id,
  repositoryId: "018f0f4d-4e45-7abc-8def-000000000031",
  goal: "Implement the focused list",
  acceptanceCriteria: ["The route is shareable"],
  competitiveMode: false,
  domainStatus: "acquired",
  presentationStatus: "RUNNING" as const,
  activeAttemptId: "A-luna-one",
  activeAgentId: "luna-one",
  attemptStatus: "started",
  attemptAuthorizedAt: timestamp,
  attemptStartedAt: timestamp,
  attemptTerminalAt: null,
  createdAt: timestamp,
  madeReadyAt: timestamp,
  acquiredAt: timestamp,
  completedAt: null,
  lastProcessedAt: timestamp
} satisfies CoordinationWorkItem;
const dependency = {
  id: "D-producer-consumer",
  producerWorkItemId: "W-producer",
  consumerWorkItemId: "W-consumer",
  producerRepositoryId: workItem.repositoryId,
  consumerRepositoryId: workItem.repositoryId,
  dependencyKind: "requires_completion",
  requiredOutput: { kind: "contract", key: "focused-ui-v1" },
  blocking: true,
  declaredAt: timestamp,
  satisfiedAt: null,
  lastProcessedAt: timestamp
} satisfies CoordinationDependency;

function render(node: ReactNode): string {
  return renderToStaticMarkup(<MemoryRouter>{node}</MemoryRouter>);
}

test("coordination collections show semantic columns, row identities, and detail links", () => {
  const changeSets = render(<ChangeSetTable hrefFor={(id) => `/change-sets/${id}`} items={[changeSet]} />);
  const workItems = render(<WorkItemTable hrefFor={(id) => `/work-items/${id}`} items={[workItem]} />);
  const dependencies = render(<DependencyTable hrefFor={(id) => `/dependencies/${id}`} items={[dependency]} />);

  assert.match(changeSets, /Keep two agents coordinated/);
  assert.match(changeSets, /<caption class="visually-hidden">ChangeSets<\/caption>/);
  assert.match(changeSets, /<th scope="col">Status<\/th>/);
  assert.match(changeSets, /scope="row"[^>]*><a aria-label="View ChangeSet CS-focused"/);
  assert.match(changeSets, /href="\/change-sets\/CS-focused"/);
  assert.match(workItems, /Implement the focused list/);
  assert.match(workItems, /luna-one/);
  assert.match(workItems, /running/);
  assert.match(workItems, /<caption class="visually-hidden">Scheduled WorkItems<\/caption>/);
  assert.match(workItems, /<th[^>]*scope="col">Attempt<\/th>/);
  assert.match(workItems, /href="\/work-items\/W-luna-one"/);
  assert.match(dependencies, /blocking/);
  assert.match(dependencies, /W-producer/);
  assert.match(dependencies, /<caption class="visually-hidden">WorkItem dependencies<\/caption>/);
  assert.match(dependencies, /<th scope="col">Consumer<\/th>/);
  assert.match(dependencies, /href="\/dependencies\/D-producer-consumer"/);
  assert.doesNotMatch(`${changeSets}${workItems}${dependencies}`, /<article/);
});

test("WorkItem detail keeps Attempt and checkpoint facts beside the selected record", () => {
  const detail = {
    workItem,
    attempt: {
      id: "A-luna-one",
      agentId: "luna-one",
      status: "started",
      selectedCandidateId: "CAND-luna-one",
      abandonmentReason: null,
      authorizedAt: timestamp,
      startedAt: timestamp,
      terminalAt: null,
      baseSnapshots: [{ repositoryId: workItem.repositoryId, objectFormat: "sha1", commitOid: "a".repeat(40) }]
    },
    checkpoint: {
      id: "CAND-luna-one",
      checkpointKind: "intermediate",
      targetBranch: "main",
      headCommitOid: "b".repeat(40),
      manifestDigest: `sha256:${"c".repeat(64)}`,
      evidenceStatus: "attributed_unverified",
      submittedAt: timestamp
    }
  } satisfies CoordinationWorkItemDetail;
  const markup = render(<WorkItemDetail detail={detail} />);

  assert.match(markup, /Current or latest Attempt/);
  assert.match(markup, /luna-one/);
  assert.match(markup, /Latest checkpoint/);
  assert.match(markup, /CAND-luna-one/);
});

test("URL-backed paging preserves filters and supports Previous recovery", () => {
  const first = new URLSearchParams("status=RUNNING&sort=LATEST_ACTIVITY_DESC");
  const second = nextPageParams(first, "cursor-one");
  const third = nextPageParams(second, "cursor-two");

  assert.equal(second.get("after"), "cursor-one");
  assert.equal(second.get("status"), "RUNNING");
  assert.equal(previousPageParams(third).get("after"), "cursor-one");
  assert.equal(previousPageParams(second).get("after"), null);
});

test("applying exact WorkItem filters trims values and resets paging", () => {
  const current = new URLSearchParams("status=RUNNING&after=cursor-two&trail=cursor-one&agent=old-agent");
  const next = exactWorkItemFilterParams(current, "  CS-focused  ", "  luna-two  ");

  assert.equal(next.get("changeSet"), "CS-focused");
  assert.equal(next.get("agent"), "luna-two");
  assert.equal(next.get("status"), "RUNNING");
  assert.equal(next.get("after"), null);
  assert.deepEqual(next.getAll("trail"), []);
});

test("detail URLs keep identities readable and return context out of the URL", () => {
  const list = "/projects/project:concurrent_development_mcp/work-items?status=RUNNING&after=cursor-one";
  const detail = detailLocation("/projects/project:concurrent_development_mcp/work-items", workItem.id);

  assert.equal(detail, `/projects/project:concurrent_development_mcp/work-items/${workItem.id}`);
  assert.equal(new URL(detail, "https://coordinator.test").search, "");
  assert.equal(safeReturnTo(list, "/projects/project:concurrent_development_mcp/work-items"), list);
  assert.equal(
    safeReturnTo("/projects/project:another/work-items", "/projects/project:concurrent_development_mcp/work-items"),
    "/projects/project:concurrent_development_mcp/work-items"
  );
  assert.equal(
    safeReturnTo("/projects/project:concurrent_development_mcp/work-items-elsewhere", "/projects/project:concurrent_development_mcp/work-items"),
    "/projects/project:concurrent_development_mcp/work-items"
  );
});

test("pagination controls expose the enabled and disabled cursor actions", () => {
  const markup = render(<PaginationControls canPrevious nextCursor="next" onNext={() => undefined} onPrevious={() => undefined} />);
  assert.match(markup, /Previous/);
  assert.match(markup, /Next/);
  assert.match(markup, /aria-label="Collection pages"/);
});
