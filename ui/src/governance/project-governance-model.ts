import type {
  AgentChoiceImpactOutcome,
  AgentChoiceKind,
  AgentChoiceStatus,
  DecisionPolicyStatus,
  GuidanceSource,
  ProjectGovernanceAgentChoiceQuery,
  ProjectGovernanceDecisionQuery,
  ProjectGovernanceGuidanceQuery,
  ProjectGovernanceQuery
} from "../gql/graphql.js";

export const DECISION_POLICY_STATUSES: ReadonlyArray<{
  readonly label: string;
  readonly value: DecisionPolicyStatus;
}> = [
  { label: "Recorded", value: "RECORDED" },
  { label: "Active", value: "ACTIVE" }
];

export const GUIDANCE_SOURCES: ReadonlyArray<{
  readonly label: string;
  readonly value: GuidanceSource;
}> = [
  { label: "MCP client", value: "MCP_CLIENT" },
  { label: "Agent forwarded", value: "AGENT_FORWARDED" }
];

export const AGENT_CHOICE_KINDS: ReadonlyArray<{
  readonly label: string;
  readonly value: AgentChoiceKind;
}> = [
  { label: "Testing framework", value: "TESTING_FRAMEWORK" }
];

export const AGENT_CHOICE_STATUSES: ReadonlyArray<{
  readonly label: string;
  readonly value: AgentChoiceStatus;
}> = [
  { label: "Recorded", value: "RECORDED" },
  { label: "Accepted", value: "ACCEPTED" },
  { label: "Invalidated", value: "INVALIDATED" }
];

export const IMPACT_OUTCOMES: ReadonlyArray<{
  readonly label: string;
  readonly value: AgentChoiceImpactOutcome;
}> = [
  { label: "Still valid", value: "STILL_VALID" },
  { label: "Invalidated", value: "INVALIDATED" },
  { label: "Not applicable", value: "NOT_APPLICABLE" },
  { label: "Already invalidated", value: "ALREADY_INVALIDATED" }
];

export interface GovernanceFilters {
  readonly decisionPolicyStatus?: DecisionPolicyStatus;
  readonly decisionTopicId?: string;
  readonly guidanceSource?: GuidanceSource;
  readonly choiceType?: AgentChoiceKind;
  readonly choiceStatus?: AgentChoiceStatus;
  readonly impactOutcome?: AgentChoiceImpactOutcome;
}

export interface GovernanceCursors {
  readonly afterDecision?: string;
  readonly afterGuidance?: string;
  readonly afterChoice?: string;
  readonly afterImpact?: string;
}

export type ProjectGovernance = NonNullable<ProjectGovernanceQuery["projectGovernance"]>;
export type GovernanceDecision = NonNullable<ProjectGovernanceDecisionQuery["projectDecision"]>;
export type GovernanceGuidance = NonNullable<ProjectGovernanceGuidanceQuery["projectGuidance"]>;
export type GovernanceAgentChoice = NonNullable<ProjectGovernanceAgentChoiceQuery["projectAgentChoice"]>;

export function preserveGovernanceForProject(
  previousData: ProjectGovernanceQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string
): ProjectGovernanceQuery | undefined {
  return previousQueryKey?.[1] === repositoryId ? previousData : undefined;
}

export function preserveDetailForIdentity<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string,
  identity: string
): T | undefined {
  return previousQueryKey?.[1] === repositoryId && previousQueryKey?.[2] === identity
    ? previousData
    : undefined;
}

export function humanized(value: string): string {
  return value.toLowerCase().replaceAll("_", " ").replaceAll(".", " · ");
}

export function badgeClass(status: string): string {
  switch (status.toLowerCase()) {
    case "active":
    case "accepted":
    case "ok":
    case "still_valid":
      return "text-bg-success";
    case "invalidated":
    case "blocked":
      return "text-bg-danger";
    case "recorded":
      return "text-bg-primary";
    default:
      return "text-bg-secondary";
  }
}
