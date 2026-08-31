import { ProjectResourcesDocument } from "../gql/graphql.js";
import type {
  ProjectResourcesQuery,
  ProjectResourcesQueryVariables,
  ResourceKind,
  ResourceLifecycleStatus
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const RESOURCE_PAGE_SIZE = 20;

export interface ResourceFilters {
  readonly resourceKind?: ResourceKind;
  readonly resourceLifecycleStatus?: ResourceLifecycleStatus;
}

export interface ResourceCursors {
  readonly activeLeasesAfter?: string;
  readonly resourcesAfter?: string;
}

export function fetchProjectResources(
  repositoryId: string,
  filters: ResourceFilters,
  cursors: ResourceCursors,
  signal?: AbortSignal
): Promise<ProjectResourcesQuery> {
  const variables: ProjectResourcesQueryVariables = {
    repositoryId,
    first: RESOURCE_PAGE_SIZE,
    ...filters,
    ...cursors
  };

  return executeGraphql(ProjectResourcesDocument, variables, signal);
}
