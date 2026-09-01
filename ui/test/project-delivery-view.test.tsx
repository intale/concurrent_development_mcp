import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  ProjectDeliveryCandidateQuery,
  ProjectDeliveryCandidatesQuery,
  ProjectDeliveryMergeQuery,
  ProjectDeliveryMergesQuery,
  ProjectDeliveryObligationsQuery,
  ProjectDeliveryReleaseQuery,
  ProjectDeliveryReleasesQuery,
  ProjectDeliveryVerificationQuery
} from "../src/gql/graphql.js";
import {
  applyFilters,
  detailLocation,
  nextPageParams,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  safeDeliveryReturnTo
} from "../src/delivery/project-delivery-model.js";
import {
  AvailableStale,
  CandidateCards,
  CandidateDetailCard,
  DeliveryNavigation,
  InitialError,
  LoadingState,
  MergeCards,
  MergeDetailCard,
  ObligationCards,
  PaginationControls,
  ReleaseCards,
  ReleaseDetailCard,
  VerificationDetailCard
} from "../src/delivery/project-delivery-view.js";

const timestamp = "2026-09-01T08:30:00.000000Z";
const projectRef = "project-reference";
const repositoryId = "018f0f4d-4e45-7abc-8def-000000000091";
const checkpoint = {
  id: "candidate-ui-10",
  changeSetId: "ui-read-model-browser-20260830",
  workItemId: "ui-10-delivery-routes",
  attemptId: "ui-10-codex-20260901",
  repositoryId,
  targetBranch: "main",
  baseCommitOid: "a".repeat(40),
  headCommitOid: "b".repeat(40),
  checkpointKind: "FINAL" as const,
  evidenceStatus: "complete",
  manifestDigest: `sha256:${"c".repeat(64)}`,
  buildContextDigest: `sha256:${"d".repeat(64)}`,
  manifestObserved: true,
  buildContextObserved: true,
  submittedAt: timestamp
};
const obligation = {
  id: "obligation-ui-10",
  kind: "candidate_relationship",
  status: "SATISFIED" as const,
  changeSetId: checkpoint.changeSetId,
  sourceCandidateId: checkpoint.id,
  targetCandidateId: "candidate-ui-09",
  sourceRepositoryId: repositoryId,
  targetRepositoryId: repositoryId,
  enforcement: "verification_gate",
  claimantId: null,
  claimExpiresAt: null,
  evidenceCount: 1,
  passedEvidenceKinds: ["rspec"],
  missingEvidenceKinds: [],
  createdAt: timestamp
};
const snapshot = {
  id: "merge-ui-10",
  repositoryId,
  targetBranch: "main",
  targetBaseCommitOid: checkpoint.baseCommitOid,
  mergeCommitOid: checkpoint.headCommitOid,
  candidateCount: 1,
  verificationStatus: "verified",
  evidenceStatus: "complete",
  producedAt: timestamp
};
const release = {
  id: "release-ui-10",
  changeSetId: checkpoint.changeSetId,
  repositoryIds: [repositoryId],
  memberCount: 1,
  status: "VERIFIED" as const,
  verificationStatus: "verified",
  releaseDigest: `sha256:${"e".repeat(64)}`,
  preparedAt: timestamp
};
const candidates = { nodes: [checkpoint], pageInfo: { endCursor: "next-candidate", hasNextPage: true } } satisfies NonNullable<ProjectDeliveryCandidatesQuery["projectCandidateCheckpoints"]>;
const obligations = { nodes: [obligation], pageInfo: { endCursor: "next-obligation", hasNextPage: true } } satisfies NonNullable<ProjectDeliveryObligationsQuery["projectVerificationObligations"]>;
const merges = { nodes: [snapshot], pageInfo: { endCursor: "next-merge", hasNextPage: true } } satisfies NonNullable<ProjectDeliveryMergesQuery["projectMergeSnapshots"]>;
const releases = { nodes: [release], pageInfo: { endCursor: "next-release", hasNextPage: true } } satisfies NonNullable<ProjectDeliveryReleasesQuery["projectReleaseSets"]>;
const candidateDetail = {
  checkpoint,
  impactDirection: "OUTGOING" as const,
  impactSurfaceDigest: `sha256:${"f".repeat(64)}`,
  impactRelationships: {
    nodes: [{
      counterpart: { ...checkpoint, id: "candidate-ui-09", workItemId: "ui-09-governance-routes" },
      relationshipKind: "path_overlap",
      reasons: [{ kind: "exact_path", matches: ["app/graphql"] }]
    }],
    pageInfo: { endCursor: "next-impact", hasNextPage: true }
  }
} satisfies NonNullable<ProjectDeliveryCandidateQuery["projectCandidateCheckpoint"]>;
const verificationDetail = {
  obligation,
  requiredEvidence: ["rspec"],
  reasons: [{ kind: "path_overlap", matches: ["app/graphql"] }],
  evidence: {
    nodes: [{ id: "evidence-ui-10", evidenceKind: "rspec", conclusion: "passed", assessmentInputDigest: `sha256:${"1".repeat(64)}`, resultDigest: `sha256:${"2".repeat(64)}`, producedAt: timestamp, submittedAt: timestamp, globalPosition: "42" }],
    pageInfo: { endCursor: "next-evidence", hasNextPage: true }
  }
} satisfies NonNullable<ProjectDeliveryVerificationQuery["projectVerificationObligation"]>;
const mergeDetail = {
  snapshot,
  candidates: [{ id: checkpoint.id, changeSetId: checkpoint.changeSetId, workItemId: checkpoint.workItemId, attemptId: checkpoint.attemptId, baseCommitOid: checkpoint.baseCommitOid, headCommitOid: checkpoint.headCommitOid, manifestDigest: checkpoint.manifestDigest }],
  authorizations: {
    nodes: [{ id: "authorization-ui-10", mergeSnapshotId: snapshot.id, outcome: "granted", policyVersion: "merge-authorization/v1", inputDigest: `sha256:${"3".repeat(64)}`, decisionDigest: `sha256:${"4".repeat(64)}`, reasonCount: 2, decidedAt: timestamp }],
    pageInfo: { endCursor: "next-authorization", hasNextPage: true }
  }
} satisfies NonNullable<ProjectDeliveryMergeQuery["projectMergeSnapshot"]>;
const releaseDetail = {
  releaseSet: release,
  members: [{ position: 1, repositoryId, targetBranch: "main", mergeSnapshotId: snapshot.id, changeSetId: checkpoint.changeSetId, mergeCommitOid: checkpoint.headCommitOid, candidateCount: 1 }],
  integrations: [{ repositoryId, attemptId: "integration-ui-10", attemptNumber: 1, outcome: "succeeded", failureCode: null, recordedAt: timestamp }],
  verificationAttemptCount: 1,
  activated: false,
  compensationRequested: false,
  completionOutcome: null
} satisfies NonNullable<ProjectDeliveryReleaseQuery["projectReleaseSet"]>;

function render(node: React.ReactNode): string {
  return renderToStaticMarkup(<MemoryRouter>{node}</MemoryRouter>);
}

test("renders four focused mobile-friendly collection views with page-slice labels", () => {
  const markup = render(<><DeliveryNavigation basePath={`/projects/${projectRef}/delivery`} /><CandidateCards connection={candidates} hrefFor={(id) => `/candidates/${id}`} /><ObligationCards connection={obligations} hrefFor={(id) => `/obligations/${id}`} /><MergeCards connection={merges} hrefFor={(id) => `/merges/${id}`} /><ReleaseCards connection={releases} hrefFor={(id) => `/releases/${id}`} /></>);
  assert.match(markup, /candidate-ui-10/);
  assert.match(markup, /obligation-ui-10/);
  assert.match(markup, /merge-ui-10/);
  assert.match(markup, /release-ui-10/);
  assert.match(markup, /1 on this page/);
  assert.match(markup, /delivery\/merge-snapshots/);
  assert.doesNotMatch(markup, /<table/);
  assert.doesNotMatch(markup, /operation batches/i);
});

test("renders focused details and bounded nested evidence without hidden bottom panels", () => {
  const markup = render(<><CandidateDetailCard detail={candidateDetail} /><VerificationDetailCard detail={verificationDetail} /><MergeDetailCard detail={mergeDetail} /><ReleaseDetailCard detail={releaseDetail} /></>);
  assert.match(markup, /exact path/);
  assert.match(markup, /evidence-ui-10/);
  assert.match(markup, /authorization-ui-10/);
  assert.match(markup, /ReleaseSet members/);
  assert.match(markup, /Integration attempts/);
  assert.doesNotMatch(markup, /raw arguments/i);
});

test("renders isolated availability, stale-refresh, and pagination states", () => {
  const markup = render(<><LoadingState label="Candidate checkpoints" /><InitialError label="Candidate checkpoints" message="Unavailable" onRetry={() => undefined} /><AvailableStale message="Refresh failed" onRetry={() => undefined} /><PaginationControls canPrevious nextCursor="next" onNext={() => undefined} onPrevious={() => undefined} /></>);
  assert.match(markup, /Loading candidate checkpoints/);
  assert.match(markup, /could not be loaded/);
  assert.match(markup, /last available content remains visible/);
  assert.match(markup, /Previous page/);
  assert.match(markup, /Next page/);
});

test("keeps filters, cursor trails, Back targets, and placeholders URL-bound", () => {
  const filtered = applyFilters(new URLSearchParams("after=old&trail=older"), { sort: "NEWEST_FIRST", status: "OPEN" });
  assert.equal(filtered.get("after"), null);
  assert.deepEqual(filtered.getAll("trail"), []);
  const next = nextPageParams(filtered, "cursor-2");
  assert.equal(next.get("after"), "cursor-2");
  assert.equal(previousPageParams(next).get("after"), null);
  const list = `/projects/${projectRef}/delivery/candidates?sort=NEWEST_FIRST`;
  assert.match(detailLocation(`/projects/${projectRef}/delivery/candidates`, checkpoint.id, list), /returnTo=/);
  assert.equal(safeDeliveryReturnTo(list, "/fallback", `/projects/${projectRef}/delivery`), list);
  assert.equal(safeDeliveryReturnTo("https://evil.invalid/", "/fallback", `/projects/${projectRef}/delivery`), "/fallback");
  const data: ProjectDeliveryCandidatesQuery = { projectCandidateCheckpoints: candidates };
  assert.equal(preserveCollection(data, ["candidates", projectRef, "filters"], projectRef, "filters"), data);
  assert.equal(preserveCollection(data, ["candidates", "other", "filters"], projectRef, "filters"), undefined);
  assert.equal(preserveDetail(candidateDetail, ["candidate", projectRef, checkpoint.id], projectRef, checkpoint.id), candidateDetail);
  assert.equal(preserveDetail(candidateDetail, ["candidate", projectRef, "other"], projectRef, checkpoint.id), undefined);
});
