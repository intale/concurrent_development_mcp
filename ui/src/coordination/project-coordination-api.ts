import {
  ProjectChangeSetDocument,
  ProjectChangeSetsDocument,
  ProjectDependenciesDocument,
  ProjectDependencyDocument,
  ProjectWorkItemDocument,
  ProjectWorkItemsDocument
} from "../gql/graphql.js";
import type {
  CoordinationPresentationStatus,
  ProjectChangeSetQuery,
  ProjectChangeSetsQuery,
  ProjectDependenciesQuery,
  ProjectDependencyQuery,
  ProjectWorkItemQuery,
  ProjectWorkItemsQuery,
  WorkItemSort
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const COORDINATION_PAGE_SIZE = 20;

export interface WorkItemFilters {
  readonly agentId?: string;
  readonly changeSetId?: string;
  readonly presentationStatuses: readonly CoordinationPresentationStatus[];
  readonly sort: WorkItemSort;
}

export function fetchProjectChangeSets(
  projectRef: string,
  after: string | undefined,
  signal?: AbortSignal
): Promise<ProjectChangeSetsQuery> {
  return executeGraphql(ProjectChangeSetsDocument, {
    projectRef,
    first: COORDINATION_PAGE_SIZE,
    ...(after ? { after } : {})
  }, signal);
}

export function fetchProjectChangeSet(
  projectRef: string,
  changeSetId: string,
  signal?: AbortSignal
): Promise<ProjectChangeSetQuery> {
  return executeGraphql(ProjectChangeSetDocument, { projectRef, changeSetId }, signal);
}

export function fetchProjectWorkItems(
  projectRef: string,
  filters: WorkItemFilters,
  after: string | undefined,
  signal?: AbortSignal
): Promise<ProjectWorkItemsQuery> {
  return executeGraphql(ProjectWorkItemsDocument, {
    projectRef,
    first: COORDINATION_PAGE_SIZE,
    presentationStatuses: filters.presentationStatuses,
    sort: filters.sort,
    ...(after ? { after } : {}),
    ...(filters.changeSetId ? { changeSetId: filters.changeSetId } : {}),
    ...(filters.agentId ? { agentId: filters.agentId } : {})
  }, signal);
}

export function fetchProjectWorkItem(
  projectRef: string,
  workItemId: string,
  signal?: AbortSignal
): Promise<ProjectWorkItemQuery> {
  return executeGraphql(ProjectWorkItemDocument, { projectRef, workItemId }, signal);
}

export function fetchProjectDependencies(
  projectRef: string,
  blocking: boolean | undefined,
  after: string | undefined,
  signal?: AbortSignal
): Promise<ProjectDependenciesQuery> {
  return executeGraphql(ProjectDependenciesDocument, {
    projectRef,
    first: COORDINATION_PAGE_SIZE,
    ...(after ? { after } : {}),
    ...(blocking === undefined ? {} : { blocking })
  }, signal);
}

export function fetchProjectDependency(
  projectRef: string,
  dependencyId: string,
  signal?: AbortSignal
): Promise<ProjectDependencyQuery> {
  return executeGraphql(ProjectDependencyDocument, { projectRef, dependencyId }, signal);
}
