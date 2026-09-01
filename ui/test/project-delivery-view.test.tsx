import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  DeliveryOperationBatchQuery,
  DeliveryOperationBatchesQuery,
  ProjectDeliveryCandidateQuery,
  ProjectDeliveryMergeQuery,
  ProjectDeliveryQuery,
  ProjectDeliveryReleaseQuery,
  ProjectDeliveryVerificationQuery
} from "../src/gql/graphql.js";
import {
  preserveForIdentity,
  preserveForProject,
  preserveGlobalIdentity
} from "../src/delivery/project-delivery-model.js";
import { ProjectDeliveryView } from "../src/delivery/project-delivery-view.js";

const timestamp = "2026-09-01T08:30:00.000000Z";
const repositoryId = "018f0f4d-4e45-7abc-8def-000000000091";
const project = { id: repositoryId, name: "Delivery browser", scope: "project:delivery-browser" };
const checkpoint = {
  id: "candidate-ui-06",
  changeSetId: "ui-read-model-browser-20260830",
  workItemId: "ui-06-delivery-browser",
  attemptId: "ui-06-codex-20260901",
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
const obligationSummary = {
  id: "obligation-ui-06",
  kind: "candidate_relationship",
  status: "SATISFIED" as const,
  changeSetId: checkpoint.changeSetId,
  sourceCandidateId: checkpoint.id,
  targetCandidateId: "candidate-ui-05",
  sourceRepositoryId: repositoryId,
  targetRepositoryId: repositoryId,
  enforcement: "required",
  claimantId: null,
  claimExpiresAt: null,
  evidenceCount: 1,
  passedEvidenceKinds: ["rspec"],
  missingEvidenceKinds: [],
  createdAt: timestamp
};
const snapshot = {
  id: "merge-ui-06",
  repositoryId,
  targetBranch: "main",
  targetBaseCommitOid: checkpoint.baseCommitOid,
  mergeCommitOid: checkpoint.headCommitOid,
  candidateCount: 1,
  verificationStatus: "verified",
  evidenceStatus: "complete",
  producedAt: timestamp
};
const releaseSummary = {
  id: "release-ui-06",
  changeSetId: checkpoint.changeSetId,
  repositoryIds: [repositoryId],
  memberCount: 1,
  status: "VERIFIED" as const,
  verificationStatus: "verified",
  releaseDigest: `sha256:${"e".repeat(64)}`,
  preparedAt: timestamp
};

const browser = {
  project,
  candidates: { nodes: [checkpoint], pageInfo: { endCursor: "next-candidate", hasNextPage: true } },
  obligations: { nodes: [obligationSummary], pageInfo: { endCursor: "next-obligation", hasNextPage: true } },
  mergeSnapshots: { nodes: [snapshot], pageInfo: { endCursor: "next-merge", hasNextPage: true } },
  releaseSets: { nodes: [releaseSummary], pageInfo: { endCursor: "next-release", hasNextPage: true } }
} satisfies NonNullable<ProjectDeliveryQuery["projectDelivery"]>;

const candidate = {
  project,
  checkpoint,
  impactDirection: "OUTGOING" as const,
  impactSurfaceDigest: `sha256:${"f".repeat(64)}`,
  impactRelationships: {
    nodes: [{
      counterpart: { ...checkpoint, id: "candidate-ui-05", workItemId: "ui-05-governance-browser" },
      relationshipKind: "path_overlap",
      reasons: [{ kind: "exact_path", matches: ["app/graphql"] }]
    }],
    pageInfo: { endCursor: "next-impact", hasNextPage: true }
  }
} satisfies NonNullable<ProjectDeliveryCandidateQuery["projectCandidateCheckpoint"]>;

const verification = {
  project,
  obligation: obligationSummary,
  requiredEvidence: ["rspec"],
  reasons: [{ kind: "path_overlap", matches: ["app/graphql"] }],
  evidence: {
    nodes: [{
      id: "evidence-ui-06",
      evidenceKind: "rspec",
      conclusion: "passed",
      assessmentInputDigest: `sha256:${"1".repeat(64)}`,
      resultDigest: `sha256:${"2".repeat(64)}`,
      producedAt: timestamp,
      submittedAt: timestamp,
      globalPosition: "42"
    }],
    pageInfo: { endCursor: "next-evidence", hasNextPage: true }
  }
} satisfies NonNullable<ProjectDeliveryVerificationQuery["projectVerificationObligation"]>;

const merge = {
  project,
  snapshot,
  candidates: [{
    id: checkpoint.id,
    changeSetId: checkpoint.changeSetId,
    workItemId: checkpoint.workItemId,
    attemptId: checkpoint.attemptId,
    baseCommitOid: checkpoint.baseCommitOid,
    headCommitOid: checkpoint.headCommitOid,
    manifestDigest: checkpoint.manifestDigest
  }],
  authorizations: {
    nodes: [{
      id: "authorization-ui-06",
      mergeSnapshotId: snapshot.id,
      outcome: "granted",
      policyVersion: "merge-authorization/v1",
      inputDigest: `sha256:${"3".repeat(64)}`,
      decisionDigest: `sha256:${"4".repeat(64)}`,
      reasonCount: 2,
      decidedAt: timestamp
    }],
    pageInfo: { endCursor: "next-authorization", hasNextPage: true }
  }
} satisfies NonNullable<ProjectDeliveryMergeQuery["projectMergeSnapshot"]>;

const release = {
  project,
  releaseSet: releaseSummary,
  members: [{
    position: 0,
    repositoryId,
    targetBranch: "main",
    mergeSnapshotId: snapshot.id,
    changeSetId: checkpoint.changeSetId,
    mergeCommitOid: checkpoint.headCommitOid,
    candidateCount: 1
  }],
  integrations: [{
    repositoryId,
    attemptId: "integration-ui-06",
    attemptNumber: 1,
    outcome: "succeeded",
    failureCode: null,
    recordedAt: timestamp
  }],
  verificationAttemptCount: 1,
  activated: false,
  compensationRequested: false,
  completionOutcome: null
} satisfies NonNullable<ProjectDeliveryReleaseQuery["projectReleaseSet"]>;

const batchSummary = {
  id: "batch-ui-06",
  targetTool: "DEVELOPMENT_ARTIFACT_CAPTURE" as const,
  status: "COMPLETED" as const,
  total: 1,
  succeeded: 1,
  rejected: 0,
  pending: 0,
  notRun: 0,
  manifestDigest: `sha256:${"5".repeat(64)}`,
  createdAt: timestamp
};
const batches = {
  nodes: [batchSummary],
  pageInfo: { endCursor: "next-batch", hasNextPage: true }
} satisfies DeliveryOperationBatchesQuery["operationBatches"];
const batch = {
  batch: batchSummary,
  items: {
    nodes: [{
      index: 0,
      targetTool: "DEVELOPMENT_ARTIFACT_CAPTURE" as const,
      commandId: "command-ui-06",
      canonicalInputDigest: `sha256:${"6".repeat(64)}`,
      status: "SUCCEEDED" as const,
      outcomeStatus: "ok",
      outcomeSummary: "Artifact captured.",
      outcomeCode: null,
      finishedAt: timestamp
    }],
    pageInfo: { endCursor: "next-batch-item", hasNextPage: true }
  }
} satisfies NonNullable<DeliveryOperationBatchQuery["operationBatch"]>;

const callbacks = {
  hrefForBatch: (id: string) => `/delivery?batch=${id}`,
  hrefForCandidate: (id: string) => `/delivery?candidate=${id}`,
  hrefForMerge: (id: string) => `/delivery?merge=${id}`,
  hrefForObligation: (id: string) => `/delivery?obligation=${id}`,
  hrefForRelease: (id: string) => `/delivery?release=${id}`,
  onNextAuthorizations: () => undefined,
  onNextBatchItems: () => undefined,
  onNextBatches: () => undefined,
  onNextCandidates: () => undefined,
  onNextEvidence: () => undefined,
  onNextImpacts: () => undefined,
  onNextMerges: () => undefined,
  onNextObligations: () => undefined,
  onNextReleases: () => undefined,
  onRetry: () => undefined
};

function render(overrides: Partial<Parameters<typeof ProjectDeliveryView>[0]> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter>
      <ProjectDeliveryView
        batch={batch}
        batches={batches}
        browser={browser}
        candidate={candidate}
        errorMessage={null}
        loading={false}
        merge={merge}
        refreshing={false}
        release={release}
        verification={verification}
        {...callbacks}
        {...overrides}
      />
    </MemoryRouter>
  );
}

test("shows typed delivery facts while keeping operation batches explicitly global", () => {
  const markup = render();
  assert.match(markup, /candidate-ui-06/);
  assert.match(markup, /exact path/);
  assert.match(markup, /evidence-ui-06/);
  assert.match(markup, /authorization-ui-06/);
  assert.match(markup, /ReleaseSet members/);
  assert.match(markup, /Global operation batches/);
  assert.match(markup, /never attributed to a project from arbitrary input/);
  assert.match(markup, /Artifact captured/);
  assert.doesNotMatch(markup, /raw arguments/i);
  assert.match(markup, /Next Candidate page/);
  assert.match(markup, /Next batch items page/);
  assert.match(markup, /aria-label="Candidate checkpoints"/);
  assert.match(markup, /aria-label="Global operation batches"/);
});

test("keeps the latest available delivery view visible when refresh fails", () => {
  const markup = render({ errorMessage: "Projection endpoint unavailable", refreshing: true });
  assert.match(markup, /last available delivery view remains visible/);
  assert.match(markup, /Refreshing latest available delivery facts/);
  assert.match(markup, /candidate-ui-06/);
});

test("renders loading, unavailable, and retryable initial errors", () => {
  const emptyDetails = { batch: null, batches: null, browser: null, candidate: null, merge: null, release: null, verification: null };
  assert.match(render({ ...emptyDetails, loading: true }), /Loading project delivery/);
  assert.match(render(emptyDetails), /not available in the latest projection/);
  assert.match(render({ ...emptyDetails, errorMessage: "Network unavailable" }), /Retry/);
});

test("preserves available data only for the same project or selected identity", () => {
  const page: ProjectDeliveryQuery = { projectDelivery: browser };
  assert.equal(preserveForProject(page, ["project-delivery", repositoryId], repositoryId), page);
  assert.equal(preserveForProject(page, ["project-delivery", "other"], repositoryId), undefined);
  assert.equal(preserveForIdentity(candidate, ["candidate", repositoryId, checkpoint.id], repositoryId, checkpoint.id), candidate);
  assert.equal(preserveForIdentity(candidate, ["candidate", repositoryId, "other"], repositoryId, checkpoint.id), undefined);
  assert.equal(preserveGlobalIdentity(batch, ["batch", batchSummary.id], batchSummary.id), batch);
  assert.equal(preserveGlobalIdentity(batch, ["batch", "other"], batchSummary.id), undefined);
});
