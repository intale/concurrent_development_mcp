import {
  GovernanceCommandReceiptDocument,
  GovernanceCommandReceiptsDocument,
  ProjectGovernanceAgentChoiceDocument,
  ProjectGovernanceDecisionDocument,
  ProjectGovernanceDocument,
  ProjectGovernanceGuidanceDocument
} from "../gql/graphql.js";
import type {
  GovernanceCommandReceiptQuery,
  GovernanceCommandReceiptQueryVariables,
  GovernanceCommandReceiptsQuery,
  GovernanceCommandReceiptsQueryVariables,
  ProjectGovernanceAgentChoiceQuery,
  ProjectGovernanceAgentChoiceQueryVariables,
  ProjectGovernanceDecisionQuery,
  ProjectGovernanceDecisionQueryVariables,
  ProjectGovernanceGuidanceQuery,
  ProjectGovernanceGuidanceQueryVariables,
  ProjectGovernanceQuery,
  ProjectGovernanceQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";
import type {
  GovernanceCursors,
  GovernanceFilters,
  ReceiptCursor,
  ReceiptFilters
} from "./project-governance-model.js";

export const GOVERNANCE_PAGE_SIZE = 20;

export function fetchProjectGovernance(
  repositoryId: string,
  filters: GovernanceFilters,
  cursors: GovernanceCursors,
  signal?: AbortSignal
): Promise<ProjectGovernanceQuery> {
  const variables: ProjectGovernanceQueryVariables = {
    repositoryId,
    first: GOVERNANCE_PAGE_SIZE,
    ...filters,
    ...cursors
  };
  return executeGraphql(ProjectGovernanceDocument, variables, signal);
}

export function fetchGovernanceDecision(
  repositoryId: string,
  decisionId: string,
  signal?: AbortSignal
): Promise<ProjectGovernanceDecisionQuery> {
  const variables: ProjectGovernanceDecisionQueryVariables = { repositoryId, decisionId };
  return executeGraphql(ProjectGovernanceDecisionDocument, variables, signal);
}

export function fetchGovernanceGuidance(
  repositoryId: string,
  messageId: string,
  interpretationsAfter?: string,
  signal?: AbortSignal
): Promise<ProjectGovernanceGuidanceQuery> {
  const variables: ProjectGovernanceGuidanceQueryVariables = {
    repositoryId,
    messageId,
    interpretationsFirst: GOVERNANCE_PAGE_SIZE,
    ...(interpretationsAfter ? { interpretationsAfter } : {})
  };
  return executeGraphql(ProjectGovernanceGuidanceDocument, variables, signal);
}

export function fetchGovernanceAgentChoice(
  repositoryId: string,
  choiceId: string,
  impactsAfter?: string,
  signal?: AbortSignal
): Promise<ProjectGovernanceAgentChoiceQuery> {
  const variables: ProjectGovernanceAgentChoiceQueryVariables = {
    repositoryId,
    choiceId,
    impactsFirst: GOVERNANCE_PAGE_SIZE,
    ...(impactsAfter ? { impactsAfter } : {})
  };
  return executeGraphql(ProjectGovernanceAgentChoiceDocument, variables, signal);
}

export function fetchCommandReceipts(
  filters: ReceiptFilters,
  cursor: ReceiptCursor,
  signal?: AbortSignal
): Promise<GovernanceCommandReceiptsQuery> {
  const variables: GovernanceCommandReceiptsQueryVariables = {
    first: GOVERNANCE_PAGE_SIZE,
    ...filters,
    ...cursor
  };
  return executeGraphql(GovernanceCommandReceiptsDocument, variables, signal);
}

export function fetchCommandReceipt(
  commandId: string,
  signal?: AbortSignal
): Promise<GovernanceCommandReceiptQuery> {
  const variables: GovernanceCommandReceiptQueryVariables = { commandId };
  return executeGraphql(GovernanceCommandReceiptDocument, variables, signal);
}
