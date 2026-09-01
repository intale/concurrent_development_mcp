import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  ProjectGovernanceAgentChoiceQuery,
  ProjectGovernanceDecisionQuery,
  ProjectGovernanceGuidanceQuery,
  ProjectGovernanceQuery
} from "../src/gql/graphql.js";
import { preserveDetailForIdentity, preserveGovernanceForProject } from "../src/governance/project-governance-model.js";
import { ProjectGovernanceView } from "../src/governance/project-governance-view.js";

const timestamp = "2026-09-01T06:30:00.000000Z";
const repositoryId = "018f0f4d-4e45-7abc-8def-000000000081";
const project = { id: repositoryId, name: "Governance browser", scope: "project:governance-browser" };
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
const impactSummary = {
  assessmentId: `choice-impact-v1:${"1".repeat(64)}`,
  choiceId: "CHO-governance",
  attemptId: "A-ui",
  outcome: "INVALIDATED" as const,
  reason: "blocking_policy_introduced",
  policyVersion: "agent-choice-decision-impact/v1",
  decisionId: "D-governance",
  decisionChangeKind: "activated",
  decisionChangedAt: timestamp,
  beforeStatus: "allowed",
  afterStatus: "blocked",
  assessedAt: timestamp
};
const choiceSummary = {
  id: "CHO-governance",
  choiceType: "TESTING_FRAMEWORK" as const,
  observationStatus: "ACCEPTED" as const,
  reasonSummary: "Use RSpec for Rails boundaries.",
  recordedAt: timestamp,
  selected: { id: "rspec", summary: "RSpec" },
  context: {
    repositoryId,
    changeSetId: "CS-ui",
    workItemId: "UI-05",
    attemptId: "A-ui",
    phase: "implementation",
    language: "ruby",
    paths: ["spec/requests/graphql"],
    environment: "test",
    agentRole: "implementer"
  }
};
const catalog = {
  project,
  decisions: { nodes: [decisionSummary], pageInfo: { endCursor: "next-decision", hasNextPage: true } },
  guidance: {
    nodes: [{
      id: "M-guidance",
      conversationId: "C-guidance",
      excerpt: "Use the approved testing boundary.",
      source: "AGENT_FORWARDED" as const,
      policyStatus: "evidence_only",
      recordedAt: timestamp,
      actor: { kind: "agent", id: "luna-1" },
      anchors: { repositoryIds: [repositoryId], changeSetId: "CS-ui", workItemId: "UI-05", attemptId: "A-ui" }
    }],
    pageInfo: { endCursor: "next-guidance", hasNextPage: true }
  },
  choices: {
    nodes: [choiceSummary],
    pageInfo: { endCursor: "next-choice", hasNextPage: true }
  },
  impacts: { nodes: [impactSummary], pageInfo: { endCursor: "next-impact", hasNextPage: true } }
} satisfies NonNullable<ProjectGovernanceQuery["projectGovernance"]>;

const decision = {
  project,
  membershipBases: ["attempt"],
  decision: {
    ...decisionSummary,
    interpretationId: "I-governance",
    sourceMessageId: "M-guidance",
    definitionDigest: `sha256:${"d".repeat(64)}`,
    rationaleSummary: "Owner approved the testing boundary.",
    correctionSummary: null,
    scope: {
      ...decisionSummary.scope,
      workspaceId: null,
      pathSelectors: ["spec/**"],
      symbolSelectors: [],
      contractSelectors: [],
      schemaSelectors: [],
      branchSelectors: [],
      environments: ["test"],
      agentRoles: ["implementer"]
    },
    conditions: { phases: ["implementation"], languages: ["ruby"], tags: [], repositoryKinds: [], artifactKinds: [], environments: [] },
    authority: { actorId: "owner", role: "project-owner" },
    enforcement: { level: "implementation_gate", retroactivity: "future_only", onViolation: "block" },
    recordedBy: { kind: "orchestrator", id: "guidance-host" },
    currentBy: { kind: "orchestrator", id: "guidance-host" },
    currentEvent: { id: repositoryId, type: "DecisionActivated", streamContext: "HumanGuidance", streamName: "Decision", streamId: "D-governance", streamRevision: 1 }
  }
} satisfies NonNullable<ProjectGovernanceDecisionQuery["projectDecision"]>;

const guidance = {
  project,
  guidance: {
    id: "M-guidance",
    conversationId: "C-guidance",
    text: "Use the approved testing boundary.",
    source: "AGENT_FORWARDED" as const,
    policyStatus: "evidence_only",
    recordedAt: timestamp,
    actor: { kind: "agent", id: "luna-1" },
    anchors: { repositoryIds: [repositoryId], changeSetId: "CS-ui", workItemId: "UI-05", attemptId: "A-ui" }
  },
  interpretations: {
    nodes: [{
      id: "I-governance",
      messageId: "M-guidance",
      lifecycleStatus: "proposed",
      policyStatus: "proposal_only",
      statementKind: "preference",
      topicId: "testing.framework",
      effect: "prefer",
      modality: "should",
      sourceSpanText: "approved testing boundary",
      assessmentStatus: "accepted_for_activation",
      assessmentReasons: ["unambiguous"],
      clarificationRequiredAt: null,
      proposedAt: timestamp,
      clarificationQuestions: [],
      actor: { kind: "agent", id: "classifier" },
      value
    }],
    pageInfo: { endCursor: "next-interpretation", hasNextPage: true }
  }
} satisfies NonNullable<ProjectGovernanceGuidanceQuery["projectGuidance"]>;

const detailedImpact = {
  ...impactSummary,
  beforeBasis: "compliant",
  beforeReasonCodes: ["selected_option_satisfies_decision"],
  afterBasis: "blocking_violation",
  afterReasonCodes: ["selected_option_violates_blocking_decision"]
};
const choice = {
  project,
  choice: {
    ...choiceSummary,
    acceptedAt: timestamp,
    invalidatedAt: timestamp,
    invalidationReason: "A blocking Decision was activated.",
    assessmentBasis: "no_policy",
    assessmentDecisionIds: ["D-governance"],
    assessmentWarnings: [],
    alternatives: [{ id: "minitest", summary: "Minitest" }],
    recordedBy: { kind: "agent", id: "luna-1" },
    acceptedBy: { kind: "agent", id: "luna-1" }
  },
  impacts: { nodes: [detailedImpact], pageInfo: { endCursor: "next-choice-impact", hasNextPage: true } }
} satisfies NonNullable<ProjectGovernanceAgentChoiceQuery["projectAgentChoice"]>;

const callbacks = {
  hrefForChoice: (id: string) => `/governance?choice=${id}`,
  hrefForDecision: (id: string) => `/governance?decision=${id}`,
  hrefForGuidance: (id: string) => `/governance?guidance=${id}`,
  onNextChoices: () => undefined,
  onNextDecisions: () => undefined,
  onNextGuidance: () => undefined,
  onNextImpacts: () => undefined,
  onNextInterpretations: () => undefined,
  onNextSelectedChoiceImpacts: () => undefined,
  onRetry: () => undefined
};

function render(overrides: Partial<Parameters<typeof ProjectGovernanceView>[0]> = {}) {
  return renderToStaticMarkup(<MemoryRouter><ProjectGovernanceView browser={catalog} choice={choice} decision={decision} errorMessage={null} guidance={guidance} loading={false} refreshing={false} {...callbacks} {...overrides} /></MemoryRouter>);
}

test("shows typed project governance details without global audit facts", () => {
  const markup = render();
  assert.match(markup, /testing\.framework/);
  assert.match(markup, /Membership/);
  assert.match(markup, /attempt/);
  assert.match(markup, /approved testing boundary/);
  assert.match(markup, /accepted for activation/);
  assert.match(markup, /AgentChoice/);
  assert.match(markup, /blocking policy introduced/);
  assert.match(markup, /Next Decisions page/);
  assert.match(markup, /aria-label="Project Decisions"/);
  assert.doesNotMatch(markup, /command receipts/i);
});

test("keeps the latest available governance view visible when refresh fails", () => {
  const markup = render({ errorMessage: "Projection endpoint unavailable", refreshing: true });
  assert.match(markup, /last available governance view remains visible/);
  assert.match(markup, /Refreshing latest available governance facts/);
  assert.match(markup, /D-governance/);
});

test("renders loading, unavailable, and retryable initial errors", () => {
  const emptyDetails = { browser: null, choice: null, decision: null, guidance: null };
  assert.match(render({ ...emptyDetails, loading: true }), /Loading project governance/);
  assert.match(render(emptyDetails), /not available in the latest projection/);
  assert.match(render({ ...emptyDetails, errorMessage: "Network unavailable" }), /Retry/);
});

test("preserves available data only for the same project and selected identity", () => {
  const page: ProjectGovernanceQuery = { projectGovernance: catalog };
  assert.equal(preserveGovernanceForProject(page, ["project-governance", repositoryId], repositoryId), page);
  assert.equal(preserveGovernanceForProject(page, ["project-governance", "other"], repositoryId), undefined);
  assert.equal(preserveDetailForIdentity(decision, ["decision", repositoryId, "D-governance"], repositoryId, "D-governance"), decision);
  assert.equal(preserveDetailForIdentity(decision, ["decision", repositoryId, "D-other"], repositoryId, "D-governance"), undefined);
});
