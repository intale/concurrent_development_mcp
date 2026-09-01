import {
  ProjectActiveResourceLeasesDocument,
  ProjectResourceDocument,
  ProjectResourceLeaseDocument,
  ProjectResourcesDocument
} from "../gql/graphql.js";
import type {
  ProjectActiveResourceLeasesQuery,
  ProjectActiveResourceLeasesQueryVariables,
  ProjectResourceLeaseQuery,
  ProjectResourceLeaseQueryVariables,
  ProjectResourceQuery,
  ProjectResourceQueryVariables,
  ProjectResourcesQuery,
  ProjectResourcesQueryVariables,
  ResourceKind,
  ResourceLifecycleStatus
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const RESOURCE_PAGE_SIZE = 20;

export interface ResourceFilters {
  readonly path?: string;
  readonly resourceKind?: ResourceKind;
  readonly resourceLifecycleStatus?: ResourceLifecycleStatus;
}

export interface LeaseFilters {
  readonly agentId?: string;
  readonly changeSetId?: string;
  readonly workItemId?: string;
  readonly attemptId?: string;
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

export function fetchProjectActiveResourceLeases(
  projectRef: string,
  filters: LeaseFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectActiveResourceLeasesQuery> {
  const variables: ProjectActiveResourceLeasesQueryVariables = {
    projectRef,
    first: RESOURCE_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectActiveResourceLeasesDocument, variables, signal);
}

export function fetchProjectResourceLease(
  projectRef: string,
  leaseId: string,
  signal?: AbortSignal
): Promise<ProjectResourceLeaseQuery> {
  const variables: ProjectResourceLeaseQueryVariables = { projectRef, leaseId };
  return executeGraphql(ProjectResourceLeaseDocument, variables, signal);
}
