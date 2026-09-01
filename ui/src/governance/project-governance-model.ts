import type {
  AgentChoiceImpactOutcome,
  AgentChoiceKind,
  AgentChoiceStatus,
  DecisionPolicyStatus,
  GovernanceChoiceSummaryFragment,
  GovernanceDecisionSummaryFragment,
  GovernanceGuidanceSummaryFragment,
  GovernanceImpactSummaryFragment,
  GuidanceSource,
  ProjectGovernanceAgentChoiceQuery,
  ProjectGovernanceAgentChoicesQuery,
  ProjectGovernanceDecisionImpactQuery,
  ProjectGovernanceDecisionImpactsQuery,
  ProjectGovernanceDecisionQuery,
  ProjectGovernanceDecisionsQuery,
  ProjectGovernanceGuidanceMessagesQuery,
  ProjectGovernanceGuidanceQuery
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

export const PAGE_START = "__governance_page_start__";

export type DecisionSummary = GovernanceDecisionSummaryFragment;
export type GuidanceSummary = GovernanceGuidanceSummaryFragment;
export type ChoiceSummary = GovernanceChoiceSummaryFragment;
export type ImpactSummary = GovernanceImpactSummaryFragment;
export type DecisionConnection = NonNullable<ProjectGovernanceDecisionsQuery["projectDecisions"]>;
export type GuidanceConnection = NonNullable<ProjectGovernanceGuidanceMessagesQuery["projectGuidanceMessages"]>;
export type ChoiceConnection = NonNullable<ProjectGovernanceAgentChoicesQuery["projectAgentChoices"]>;
export type ImpactConnection = NonNullable<ProjectGovernanceDecisionImpactsQuery["projectDecisionImpacts"]>;
export type DecisionDetail = NonNullable<ProjectGovernanceDecisionQuery["projectDecision"]>;
export type GuidanceDetail = NonNullable<ProjectGovernanceGuidanceQuery["projectGuidance"]>;
export type ChoiceDetail = NonNullable<ProjectGovernanceAgentChoiceQuery["projectAgentChoice"]>;
export type ImpactDetail = NonNullable<ProjectGovernanceDecisionImpactQuery["projectDecisionImpact"]>;

export function preserveCollection<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  filterKey: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === filterKey
    ? previousData
    : undefined;
}

export function preserveDetail<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  identity: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === identity
    ? previousData
    : undefined;
}

export function applyFilters(
  params: URLSearchParams,
  filters: Readonly<Record<string, string>>
): URLSearchParams {
  const next = new URLSearchParams(params);
  next.delete("after");
  next.delete("trail");
  Object.entries(filters).forEach(([key, value]) => {
    const normalized = value.trim();
    if (normalized) next.set(key, normalized);
    else next.delete(key);
  });
  return next;
}

export function nextPageParams(params: URLSearchParams, cursor: string): URLSearchParams {
  const next = new URLSearchParams(params);
  next.append("trail", params.get("after") ?? PAGE_START);
  next.set("after", cursor);
  return next;
}

export function previousPageParams(params: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(params);
  const trail = next.getAll("trail");
  const previous = trail.pop();
  next.delete("trail");
  trail.forEach((cursor) => next.append("trail", cursor));
  if (!previous || previous === PAGE_START) next.delete("after");
  else next.set("after", previous);
  return next;
}

export function listLocation(pathname: string, params: URLSearchParams): string {
  const query = params.toString();
  return query ? `${pathname}?${query}` : pathname;
}

export function detailLocation(pathname: string, identity: string, returnTo: string): string {
  const query = new URLSearchParams({ returnTo }).toString();
  return `${pathname}/${encodeURIComponent(identity)}?${query}`;
}

export function safeGovernanceReturnTo(
  value: string | null,
  fallback: string,
  governanceBasePath: string
): string {
  return value === governanceBasePath || value?.startsWith(`${governanceBasePath}/`)
    ? value
    : fallback;
}

export function matching<T extends string>(
  requested: string | null,
  options: ReadonlyArray<{ readonly value: T }>
): T | undefined {
  return options.some(({ value }) => value === requested) ? requested as T : undefined;
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
