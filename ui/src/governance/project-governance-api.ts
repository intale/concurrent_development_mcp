import {
  ProjectGovernanceAgentChoiceDocument,
  ProjectGovernanceAgentChoicesDocument,
  ProjectGovernanceDecisionDocument,
  ProjectGovernanceDecisionImpactDocument,
  ProjectGovernanceDecisionImpactsDocument,
  ProjectGovernanceDecisionsDocument,
  ProjectGovernanceGuidanceDocument,
  ProjectGovernanceGuidanceMessagesDocument
} from "../gql/graphql.js";
import type {
  AgentChoiceImpactOutcome,
  AgentChoiceKind,
  AgentChoiceStatus,
  DecisionPolicyStatus,
  GuidanceSource,
  LatestUpdateSort,
  ProjectGovernanceAgentChoiceQuery,
  ProjectGovernanceAgentChoiceQueryVariables,
  ProjectGovernanceAgentChoicesQuery,
  ProjectGovernanceAgentChoicesQueryVariables,
  ProjectGovernanceDecisionImpactQuery,
  ProjectGovernanceDecisionImpactQueryVariables,
  ProjectGovernanceDecisionImpactsQuery,
  ProjectGovernanceDecisionImpactsQueryVariables,
  ProjectGovernanceDecisionQuery,
  ProjectGovernanceDecisionQueryVariables,
  ProjectGovernanceDecisionsQuery,
  ProjectGovernanceDecisionsQueryVariables,
  ProjectGovernanceGuidanceMessagesQuery,
  ProjectGovernanceGuidanceMessagesQueryVariables,
  ProjectGovernanceGuidanceQuery,
  ProjectGovernanceGuidanceQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const GOVERNANCE_PAGE_SIZE = 20;

export interface DecisionFilters {
  readonly policyStatus?: DecisionPolicyStatus;
  readonly topicId?: string;
  readonly sort: LatestUpdateSort;
}

export interface GuidanceFilters {
  readonly source?: GuidanceSource;
  readonly sort: LatestUpdateSort;
}

export interface ChoiceFilters {
  readonly choiceType?: AgentChoiceKind;
  readonly status?: AgentChoiceStatus;
  readonly sort: LatestUpdateSort;
}

export interface ImpactFilters {
  readonly outcome?: AgentChoiceImpactOutcome;
  readonly sort: LatestUpdateSort;
}

export function fetchGovernanceDecisions(
  projectRef: string,
  filters: DecisionFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectGovernanceDecisionsQuery> {
  const variables: ProjectGovernanceDecisionsQueryVariables = {
    projectRef,
    first: GOVERNANCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectGovernanceDecisionsDocument, variables, signal);
}

export function fetchGovernanceGuidanceMessages(
  projectRef: string,
  filters: GuidanceFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectGovernanceGuidanceMessagesQuery> {
  const variables: ProjectGovernanceGuidanceMessagesQueryVariables = {
    projectRef,
    first: GOVERNANCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectGovernanceGuidanceMessagesDocument, variables, signal);
}

export function fetchGovernanceAgentChoices(
  projectRef: string,
  filters: ChoiceFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectGovernanceAgentChoicesQuery> {
  const variables: ProjectGovernanceAgentChoicesQueryVariables = {
    projectRef,
    first: GOVERNANCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectGovernanceAgentChoicesDocument, variables, signal);
}

export function fetchGovernanceDecisionImpacts(
  projectRef: string,
  filters: ImpactFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectGovernanceDecisionImpactsQuery> {
  const variables: ProjectGovernanceDecisionImpactsQueryVariables = {
    projectRef,
    first: GOVERNANCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectGovernanceDecisionImpactsDocument, variables, signal);
}

export function fetchGovernanceDecision(
  projectRef: string,
  decisionId: string,
  signal?: AbortSignal
): Promise<ProjectGovernanceDecisionQuery> {
  const variables: ProjectGovernanceDecisionQueryVariables = { projectRef, decisionId };
  return executeGraphql(ProjectGovernanceDecisionDocument, variables, signal);
}

export function fetchGovernanceGuidance(
  projectRef: string,
  messageId: string,
  interpretationsAfter: string | null,
  signal?: AbortSignal
): Promise<ProjectGovernanceGuidanceQuery> {
  const variables: ProjectGovernanceGuidanceQueryVariables = {
    projectRef,
    messageId,
    interpretationsFirst: GOVERNANCE_PAGE_SIZE,
    ...(interpretationsAfter ? { interpretationsAfter } : {})
  };
  return executeGraphql(ProjectGovernanceGuidanceDocument, variables, signal);
}

export function fetchGovernanceAgentChoice(
  projectRef: string,
  choiceId: string,
  impactsAfter: string | null,
  signal?: AbortSignal
): Promise<ProjectGovernanceAgentChoiceQuery> {
  const variables: ProjectGovernanceAgentChoiceQueryVariables = {
    projectRef,
    choiceId,
    impactsFirst: GOVERNANCE_PAGE_SIZE,
    ...(impactsAfter ? { impactsAfter } : {})
  };
  return executeGraphql(ProjectGovernanceAgentChoiceDocument, variables, signal);
}

export function fetchGovernanceDecisionImpact(
  projectRef: string,
  assessmentId: string,
  signal?: AbortSignal
): Promise<ProjectGovernanceDecisionImpactQuery> {
  const variables: ProjectGovernanceDecisionImpactQueryVariables = { projectRef, assessmentId };
  return executeGraphql(ProjectGovernanceDecisionImpactDocument, variables, signal);
}
