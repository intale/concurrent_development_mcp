import { ProjectsDocument, ProjectWorkspaceDocument } from "../gql/graphql.js";
import type {
  ProjectsQuery,
  ProjectsQueryVariables,
  ProjectSort,
  ProjectWorkspaceQuery,
  ProjectWorkspaceQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const PROJECT_PAGE_SIZE = 20;
export const PROJECT_REPOSITORY_PREVIEW_SIZE = 3;
export const PROJECT_REPOSITORY_PAGE_SIZE = 20;

export interface ProjectCatalogFilters {
  readonly search?: string;
  readonly sort: ProjectSort;
}

export function projectWorkspaceQueryKey(projectRef: string, first: number, after: string | null) {
  return ["project-workspace", projectRef, first, after] as const;
}

export function fetchProjects(
  filters: ProjectCatalogFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectsQuery> {
  const variables: ProjectsQueryVariables = {
    first: PROJECT_PAGE_SIZE,
    repositoriesFirst: PROJECT_REPOSITORY_PREVIEW_SIZE,
    sort: filters.sort,
    ...(filters.search ? { search: filters.search } : {}),
    ...(after ? { after } : {})
  };

  return executeGraphql(ProjectsDocument, variables, signal);
}

export function fetchProjectWorkspace(
  projectRef: string,
  first: number,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectWorkspaceQuery> {
  const variables: ProjectWorkspaceQueryVariables = {
    projectRef,
    first,
    ...(after ? { after } : {})
  };

  return executeGraphql(ProjectWorkspaceDocument, variables, signal);
}
