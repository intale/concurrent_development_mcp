import type { ProjectSort } from "../gql/graphql.js";

export interface ProjectRepositoryPreview {
  readonly displayName: string;
  readonly id: string;
  readonly paths: readonly string[];
}

export interface ProjectRow {
  readonly displayLabel: string;
  readonly hasMoreRepositories: boolean;
  readonly projectRef: string;
  readonly repositories: readonly ProjectRepositoryPreview[];
  readonly repositoryCount: number;
  readonly scope: string;
}

export const DEFAULT_PROJECT_SORT: ProjectSort = "NEWEST_FIRST";

export function parseProjectSort(value: string | null): ProjectSort {
  return value === "OLDEST_FIRST" ? "OLDEST_FIRST" : DEFAULT_PROJECT_SORT;
}

export function preservePageForCatalogFilters<TData>(
  previousData: TData | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  search: string,
  sort: ProjectSort
): TData | undefined {
  return previousQueryKey?.[1] === search && previousQueryKey[2] === sort
    ? previousData
    : undefined;
}

export function nextProjectPageParameters(
  current: URLSearchParams,
  endCursor: string
): URLSearchParams {
  const next = new URLSearchParams(current);
  next.append("trail", next.get("after") ?? "");
  next.set("after", endCursor);
  return next;
}

export function previousProjectPageParameters(current: URLSearchParams): URLSearchParams {
  const previous = new URLSearchParams(current);
  const trail = previous.getAll("trail");
  const after = trail.pop();
  previous.delete("trail");
  trail.forEach((cursor) => previous.append("trail", cursor));
  if (after) {
    previous.set("after", after);
  } else {
    previous.delete("after");
  }
  return previous;
}

export function resetProjectPagination(parameters: URLSearchParams): URLSearchParams {
  const reset = new URLSearchParams(parameters);
  reset.delete("after");
  reset.delete("trail");
  return reset;
}
