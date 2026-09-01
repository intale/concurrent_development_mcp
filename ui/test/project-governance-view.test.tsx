import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  ChoiceConnection,
  ChoiceDetail,
  DecisionConnection,
  DecisionDetail,
  GuidanceConnection,
  GuidanceDetail,
  ImpactConnection,
  ImpactDetail
} from "../src/governance/project-governance-model.js";
import {
  detailLocation,
  nextPageParams,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  safeGovernanceReturnTo
} from "../src/governance/project-governance-model.js";
import {
  AvailableStale,
  ChoiceCards,
  ChoiceDetailCard,
  DecisionCards,
  DecisionDetailCard,
  GovernanceNavigation,
  GuidanceCards,
  GuidanceDetailCard,
  ImpactCards,
  ImpactDetailCard,
  InitialError,
  LoadingState,
  PaginationControls
} from "../src/governance/project-governance-view.js";

const timestamp = "2026-09-01T06:30:00.000000Z";
const projectRef = "project-ref-governance";
const repositoryId = "018f0f4d-4e45-7abc-8def-000000000081";
const assessmentId = `choice-impact-v1:${"1".repeat(64)}`;
const value = { schema: "named-choice/v1", name: "rspec", items: null, targetKind: null, targetId: null, action: null };
const decisionSummary = {
  id: "D-governance",
  topicId: "testing.framework",
  policyStatus: "ACTIVE" as const,
  statementKind: "preference",
  effect: "prefer",
  modality: "should",
  recordedAt: timestamp,
  currentAt: timestamp,
  correctionCount: 0,
  scope: { repositoryIds: [repositoryId], changeSetId: "CS-ui", workItemId: "UI-05", attemptId: "A-ui", candidateId: null },
  value
};
const guidanceSummary = {
  id: "M-guidance",
  conversationId: "C-guidance",
  excerpt: "Use the approved testing boundary.",
  source: "AGENT_FORWARDED" as const,
  policyStatus: "evidence_only",
  recordedAt: timestamp,
  actor: { kind: "agent", id: "luna-1" },
  anchors: { repositoryIds: [repositoryId], changeSetId: "CS-ui", workItemId: "UI-05", attemptId: "A-ui" }
};
const choiceSummary = {
  id: "CHO-governance",
  choiceType: "TESTING_FRAMEWORK" as const,
  observationStatus: "ACCEPTED" as const,
  reasonSummary: "Use RSpec for Rails boundaries.",
  recordedAt: timestamp,
  selected: { id: "rspec", summary: "RSpec" },
  context: { repositoryId, changeSetId: "CS-ui", workItemId: "UI-05", attemptId: "A-ui", phase: "implementation", language: "ruby", paths: ["spec/requests/graphql"], environment: "test", agentRole: "implementer" }
};
const impactSummary = {
  assessmentId,
  choiceId: "CHO-governance",
  attemptId: "A-ui",
  outcome: "INVALIDATED" as const,
  reason: "blocking_policy_introduced",
  policyVersion: "agent-choice-decision-impact/v1",
  decisionId: "D-governance",
  decisionChangeKind: "activated",
  decisionChangedAt: timestamp,
  beforeStatus: "allowed",
  beforeBasis: "compliant",
  beforeReasonCodes: ["selected_option_satisfies_decision"],
  afterStatus: "blocked",
  afterBasis: "blocking_violation",
  afterReasonCodes: ["selected_option_violates_blocking_decision"],
  assessedAt: timestamp
};

const decisions = { nodes: [decisionSummary], pageInfo: { endCursor: "next-decision", hasNextPage: true } } satisfies DecisionConnection;
const guidance = { nodes: [guidanceSummary], pageInfo: { endCursor: "next-guidance", hasNextPage: true } } satisfies GuidanceConnection;
const choices = { nodes: [choiceSummary], pageInfo: { endCursor: "next-choice", hasNextPage: true } } satisfies ChoiceConnection;
const impacts = { nodes: [impactSummary], pageInfo: { endCursor: "next-impact", hasNextPage: true } } satisfies ImpactConnection;
const decision = {
  membershipBases: ["attempt"],
  decision: {
    ...decisionSummary,
    interpretationId: "I-governance",
    sourceMessageId: "M-guidance",
    definitionDigest: `sha256:${"d".repeat(64)}`,
    rationaleSummary: "Owner approved the testing boundary.",
    correctionSummary: null,
    scope: { ...decisionSummary.scope, workspaceId: null, pathSelectors: ["spec/**"], symbolSelectors: [], contractSelectors: [], schemaSelectors: [], branchSelectors: [], environments: ["test"], agentRoles: ["implementer"] },
    conditions: { phases: ["implementation"], languages: ["ruby"], tags: [], repositoryKinds: [], artifactKinds: [], environments: [] },
    authority: { actorId: "owner", role: "project-owner" },
    enforcement: { level: "implementation_gate", retroactivity: "future_only", onViolation: "block" },
    recordedBy: { kind: "orchestrator", id: "guidance-host" },
    currentBy: { kind: "orchestrator", id: "guidance-host" },
    currentEvent: { id: repositoryId, type: "DecisionActivated", streamContext: "HumanGuidance", streamName: "Decision", streamId: "D-governance", streamRevision: 1 }
  }
} satisfies DecisionDetail;
const guidanceDetail = {
  guidance: { ...guidanceSummary, text: "Use the approved testing boundary." },
  interpretations: {
    nodes: [{ id: "I-governance", messageId: "M-guidance", lifecycleStatus: "proposed", policyStatus: "proposal_only", statementKind: "preference", topicId: "testing.framework", effect: "prefer", modality: "should", sourceSpanText: "approved testing boundary", assessmentStatus: "accepted_for_activation", assessmentReasons: ["unambiguous"], clarificationRequiredAt: null, proposedAt: timestamp, clarificationQuestions: [], actor: { kind: "agent", id: "classifier" }, value }],
    pageInfo: { endCursor: "next-interpretation", hasNextPage: true }
  }
} satisfies GuidanceDetail;
const choiceDetail = {
  choice: { ...choiceSummary, acceptedAt: timestamp, invalidatedAt: timestamp, invalidationReason: "A blocking Decision was activated.", assessmentBasis: "no_policy", assessmentDecisionIds: ["D-governance"], assessmentWarnings: [], alternatives: [{ id: "minitest", summary: "Minitest" }], recordedBy: { kind: "agent", id: "luna-1" }, acceptedBy: { kind: "agent", id: "luna-1" } },
  impacts
} satisfies ChoiceDetail;
const impactDetail = { impact: impactSummary } satisfies ImpactDetail;

function render(node: React.ReactNode): string {
  return renderToStaticMarkup(<MemoryRouter>{node}</MemoryRouter>);
}

test("presents four focused Governance collections with stable detail actions", () => {
  const markup = render(<><GovernanceNavigation basePath={`/projects/${projectRef}/governance`} /><DecisionCards connection={decisions} hrefFor={(id) => `/decisions/${id}`} /><GuidanceCards connection={guidance} hrefFor={(id) => `/guidance/${id}`} /><ChoiceCards connection={choices} hrefFor={(id) => `/choices/${id}`} /><ImpactCards connection={impacts} hrefFor={(id) => `/impacts/${id}`} /></>);
  assert.match(markup, /Governance views/);
  assert.match(markup, /Project Decisions/);
  assert.match(markup, /approved testing boundary/);
  assert.match(markup, /Use RSpec for Rails boundaries/);
  assert.match(markup, /View impact/);
  assert.match(markup, /href="\/decisions\/D-governance"/);
  assert.doesNotMatch(markup, /<table/);
});

test("keeps each substantial Governance detail in its own in-context page", () => {
  const markup = render(<><DecisionDetailCard backTo="/decisions" detail={decision} /><GuidanceDetailCard backTo="/guidance" detail={guidanceDetail} /><ChoiceDetailCard backTo="/choices" detail={choiceDetail} impactHref={(id) => `/impacts/${id}`} /><ImpactDetailCard backTo="/impacts" choiceHref="/choices/CHO-governance" decisionHref="/decisions/D-governance" detail={impactDetail} /></>);
  assert.match(markup, /Membership basis/);
  assert.match(markup, /accepted for activation/);
  assert.match(markup, /Alternatives considered/);
  assert.match(markup, /Before/);
  assert.match(markup, /After/);
  assert.match(markup, /Back to Decisions/);
  assert.match(markup, /View AgentChoice/);
});

test("keeps available content visible during refresh failures and provides explicit initial states", () => {
  assert.match(render(<><AvailableStale message="Projection unavailable" onRetry={() => undefined} /><DecisionCards connection={decisions} hrefFor={() => "/decision"} /></>), /last available projection remains visible/);
  assert.match(render(<LoadingState label="Decisions" />), /Loading Decisions/);
  assert.match(render(<InitialError label="Decisions" message="Network unavailable" onRetry={() => undefined} />), /Retry/);
});

test("binds preserved data, pagination trails, and return locations to the same Project", () => {
  const page = { projectDecisions: decisions };
  assert.equal(preserveCollection(page, ["decisions", projectRef, "filters"], projectRef, "filters"), page);
  assert.equal(preserveCollection(page, ["decisions", "other", "filters"], projectRef, "filters"), undefined);
  assert.equal(preserveDetail(decision, ["decision", projectRef, "D-governance"], projectRef, "D-governance"), decision);
  assert.equal(preserveDetail(decision, ["decision", projectRef, "D-other"], projectRef, "D-governance"), undefined);

  const first = new URLSearchParams("status=ACTIVE");
  const second = nextPageParams(first, "cursor-2");
  assert.equal(second.get("after"), "cursor-2");
  assert.equal(previousPageParams(second).get("after"), null);
  assert.match(detailLocation("/governance/decisions", "D one", "/governance/decisions?status=ACTIVE"), /D%20one/);
  assert.equal(safeGovernanceReturnTo("https://example.test", "/fallback", "/projects/p/governance"), "/fallback");
});

test("renders explicit previous and next controls for cursor navigation", () => {
  const markup = render(<PaginationControls canPrevious nextCursor="next" onNext={() => undefined} onPrevious={() => undefined} />);
  assert.match(markup, /Previous/);
  assert.match(markup, /Next/);
});
