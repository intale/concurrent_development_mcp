import { ProjectCoordinationDocument } from "../gql/graphql.js";
import type {
  CoordinationPresentationStatus,
  ProjectCoordinationQuery,
  ProjectCoordinationQueryVariables,
  WorkItemSort
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const COORDINATION_PAGE_SIZE = 20;

export interface CoordinationFilters {
  readonly blocking?: boolean;
  readonly presentationStatuses: readonly CoordinationPresentationStatus[];
  readonly workItemSort: WorkItemSort;
}

export interface CoordinationCursors {
  readonly changeSetsAfter?: string;
  readonly dependenciesAfter?: string;
  readonly workItemsAfter?: string;
}

export function fetchProjectCoordination(
  repositoryId: string,
  filters: CoordinationFilters,
  cursors: CoordinationCursors,
  signal?: AbortSignal
): Promise<ProjectCoordinationQuery> {
  const variables: ProjectCoordinationQueryVariables = {
    repositoryId,
    first: COORDINATION_PAGE_SIZE,
    presentationStatuses: filters.presentationStatuses,
    workItemSort: filters.workItemSort,
    ...(filters.blocking === undefined ? {} : { blocking: filters.blocking }),
    ...cursors
  };

  return executeGraphql(ProjectCoordinationDocument, variables, signal);
}
