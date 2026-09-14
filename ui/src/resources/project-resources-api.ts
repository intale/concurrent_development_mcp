import {
  ProjectActiveResourceWorkIntentionsDocument,
  ProjectResourceDocument,
  ProjectResourceWorkIntentionDocument,
  ProjectResourcesDocument
} from "../gql/graphql.js";
import type {
  ProjectActiveResourceWorkIntentionsQuery,
  ProjectActiveResourceWorkIntentionsQueryVariables,
  ProjectResourceWorkIntentionQuery,
  ProjectResourceWorkIntentionQueryVariables,
  ProjectResourceQuery,
  ProjectResourceQueryVariables,
  ProjectResourcesQuery,
  ProjectResourcesQueryVariables,
  LatestUpdateSort,
  ResourceKind,
  ResourceLifecycleStatus,
  ResourceWorkIntentionMode
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const RESOURCE_PAGE_SIZE = 20;

export interface ResourceFilters {
  readonly path?: string;
  readonly resourceKind?: ResourceKind;
  readonly resourceLifecycleStatus?: ResourceLifecycleStatus;
  readonly sort: LatestUpdateSort;
}

export interface WorkIntentionFilters {
  readonly agentId?: string;
  readonly changeSetId?: string;
  readonly workItemId?: string;
  readonly attemptId?: string;
  readonly mode?: ResourceWorkIntentionMode;
  readonly sort: LatestUpdateSort;
}

export function fetchProjectResources(
  projectRef: string,
  filters: ResourceFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectResourcesQuery> {
  const variables: ProjectResourcesQueryVariables = {
    projectRef,
    first: RESOURCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectResourcesDocument, variables, signal);
}

export function fetchProjectResource(
  projectRef: string,
  resourceId: string,
  signal?: AbortSignal
): Promise<ProjectResourceQuery> {
  const variables: ProjectResourceQueryVariables = { projectRef, resourceId };
  return executeGraphql(ProjectResourceDocument, variables, signal);
}

export function fetchProjectActiveResourceWorkIntentions(
  projectRef: string,
  filters: WorkIntentionFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectActiveResourceWorkIntentionsQuery> {
  const variables: ProjectActiveResourceWorkIntentionsQueryVariables = {
    projectRef,
    first: RESOURCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectActiveResourceWorkIntentionsDocument, variables, signal);
}

export function fetchProjectResourceWorkIntention(
  projectRef: string,
  intentionId: string,
  signal?: AbortSignal
): Promise<ProjectResourceWorkIntentionQuery> {
  const variables: ProjectResourceWorkIntentionQueryVariables = { projectRef, intentionId };
  return executeGraphql(ProjectResourceWorkIntentionDocument, variables, signal);
}
