import assert from "node:assert/strict";
import test from "node:test";
import type { ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type { ProjectResource, ResourceLease } from "../src/resources/project-resources-model.js";
import {
  applyFilters,
  detailLocation,
  nextPageParams,
  previousPageParams,
  safeReturnTo
} from "../src/resources/project-resources-model.js";
import {
  AvailableStale,
  LeaseCards,
  LeaseDetail,
  PaginationControls,
  ResourceCards,
  ResourceDetail,
  ResourceNavigation
} from "../src/resources/project-resources-view.js";

const projectRef = "project-ref";
const timestamp = "2026-08-31T12:00:00.000000Z";
const resource = {
  id: "018f0f4d-4e45-7abc-8def-000000000062",
  repositoryId: "018f0f4d-4e45-7abc-8def-000000000061",
  kind: "FILE" as const,
  path: "app/models/leased.rb",
  lifecycleStatus: "CURRENT" as const,
  unbindingReason: null,
  registeredEventId: "018f0f4d-4e45-7abc-8def-000000000063",
  registeredActorId: "luna-registrar",
  registeredAt: timestamp,
  latestTransitionEventId: "018f0f4d-4e45-7abc-8def-000000000064",
  latestTransitionActorId: "luna-binder",
  lastTransitionAt: timestamp
} satisfies ProjectResource;
const lease = {
  id: "018f0f4d-4e45-7abc-8def-000000000065",
  leaseSetId: "018f0f4d-4e45-7abc-8def-000000000066",
  resourceId: resource.id,
  repositoryId: resource.repositoryId,
  resourceKind: "FILE" as const,
  resourcePath: resource.path,
  resourceLifecycleStatus: "CURRENT" as const,
  status: "EXPIRED" as const,
  baseBlobOid: "b".repeat(40),
  fencingToken: "7",
  policyVersion: "coordinator-resource-lease/v2",
  changeSetId: "CS-resources",
  workItemId: "W-owner",
  attemptId: "A-owner",
  agentId: "luna-owner",
  reservedEventId: "018f0f4d-4e45-7abc-8def-000000000067",
  lastExpandedEventId: null,
  lastRenewedEventId: null,
  releaseEventId: null,
  attemptTerminalEventId: null,
  reservedAt: timestamp,
  lastExpandedAt: null,
  lastRenewedAt: null,
  previousExpiresAt: null,
  expiresAt: timestamp,
  releasedAt: null,
  attemptTerminalAt: null,
  lastProjectedAt: timestamp
} satisfies ResourceLease;

function render(node: ReactNode, route = "/") {
  return renderToStaticMarkup(<MemoryRouter initialEntries={[route]}>{node}</MemoryRouter>);
}

test("resource and active-lease collections lead with meaning and an adjacent primary action", () => {
  const resourceMarkup = render(
    <ResourceCards
      connection={{ nodes: [resource], pageInfo: { endCursor: "next", hasNextPage: true } }}
      hrefFor={(id) => `/resources/${id}`}
    />
  );
  const leaseMarkup = render(
    <LeaseCards
      connection={{ asOf: timestamp, nodes: [{ ...lease, status: "ACTIVE" }], pageInfo: { endCursor: null, hasNextPage: false } }}
      hrefFor={(id) => `/leases/${id}`}
    />
  );

  assert.match(resourceMarkup, /app\/models\/leased.rb/);
  assert.match(resourceMarkup, /current/);
  assert.match(resourceMarkup, /View Resource/);
  assert.match(resourceMarkup, /class="btn btn-primary align-self-start mt-auto"/);
  assert.match(leaseMarkup, /Holder:<\/strong> luna-owner/);
  assert.match(leaseMarkup, /W-owner/);
  assert.match(leaseMarkup, /View lease/);
  assert.match(leaseMarkup, /Ownership comes only from projected lease facts/);
});

test("focused details place Back and related navigation with the selected content", () => {
  const resourceMarkup = render(<ResourceDetail backTo="/inventory?path=app" resource={resource} />);
  const leaseMarkup = render(
    <LeaseDetail backTo="/leases?agent=luna-owner" lease={lease} projectPath={`/projects/${projectRef}`} />
  );

  assert.match(resourceMarkup, /Registration/);
  assert.match(resourceMarkup, /luna-registrar/);
  assert.match(resourceMarkup, /Back to Resource inventory/);
  assert.match(leaseMarkup, /expired/);
  assert.match(leaseMarkup, /View WorkItem/);
  assert.match(leaseMarkup, /View Resource/);
  assert.match(leaseMarkup, /Back to active leases/);
});

test("Resource subnavigation and recoverable pagination are explicit", () => {
  const markup = render(
    <>
      <ResourceNavigation basePath={`/projects/${projectRef}/resources`} />
      <PaginationControls canPrevious nextCursor="next" onNext={() => undefined} onPrevious={() => undefined} />
    </>,
    `/projects/${projectRef}/resources/inventory`
  );

  assert.match(markup, /aria-label="Resource views"/);
  assert.match(markup, /Resource inventory/);
  assert.match(markup, /Active leases/);
  assert.match(markup, /Previous/);
  assert.match(markup, /Next/);
});

test("filter, paging, detail, and Back state remain URL-backed and bounded", () => {
  const filtered = applyFilters(new URLSearchParams("after=old&trail=start"), {
    path: " app/models ",
    kind: "FILE",
    lifecycle: ""
  });
  const next = nextPageParams(filtered, "next-cursor");
  const previous = previousPageParams(next);
  const listPath = `/projects/${projectRef}/resources/inventory`;
  const detail = detailLocation(listPath, resource.id, `${listPath}?${filtered.toString()}`);

  assert.equal(filtered.get("path"), "app/models");
  assert.equal(filtered.get("kind"), "FILE");
  assert.equal(filtered.has("after"), false);
  assert.equal(next.get("after"), "next-cursor");
  assert.equal(previous.get("after"), null);
  assert.match(detail, /returnTo=/);
  assert.equal(safeReturnTo(`${listPath}?path=app`, listPath), `${listPath}?path=app`);
  assert.equal(safeReturnTo("https://example.test", listPath), listPath);
});

test("available data stays visible beside a localized refresh failure", () => {
  const markup = render(
    <>
      <AvailableStale message="Projection endpoint unavailable" onRetry={() => undefined} />
      <ResourceCards
        connection={{ nodes: [resource], pageInfo: { endCursor: null, hasNextPage: false } }}
        hrefFor={() => "/resource"}
      />
    </>
  );

  assert.match(markup, /last available projection remains visible/);
  assert.match(markup, /Projection endpoint unavailable/);
  assert.match(markup, /app\/models\/leased.rb/);
});
