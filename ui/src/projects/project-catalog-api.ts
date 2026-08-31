import { ProjectsDocument } from "../gql/graphql.js";
import type { ProjectsQuery, ProjectsQueryVariables } from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const PROJECT_PAGE_SIZE = 20;

export function fetchProjects(
  scope: string,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectsQuery> {
  const variables: ProjectsQueryVariables = {
    scope,
    first: PROJECT_PAGE_SIZE,
    ...(after ? { after } : {})
  };

  return executeGraphql(ProjectsDocument, variables, signal);
}
