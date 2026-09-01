import type {
  CoordinationChangeSetFieldsFragment,
  CoordinationDependencyFieldsFragment,
  CoordinationPresentationStatus,
  CoordinationWorkItemFieldsFragment,
  ProjectWorkItemQuery,
  WorkItemSort
} from "../gql/graphql.js";

export const PRESENTATION_STATUSES: readonly CoordinationPresentationStatus[] = [
  "PENDING",
  "READY",
  "ASSIGNED",
  "RUNNING",
  "COMPLETED"
];

export const WORK_ITEM_SORTS: ReadonlyArray<{ readonly label: string; readonly value: WorkItemSort }> = [
  { label: "Work item ID", value: "WORK_ITEM_ID_ASC" },
  { label: "Status", value: "STATUS_ASC" },
  { label: "Latest activity", value: "LATEST_ACTIVITY_DESC" }
];

export const PAGE_START = "__coordination_page_start__";

export type CoordinationChangeSet = CoordinationChangeSetFieldsFragment;
export type CoordinationWorkItem = CoordinationWorkItemFieldsFragment;
export type CoordinationDependency = CoordinationDependencyFieldsFragment;
export type CoordinationWorkItemDetail = NonNullable<ProjectWorkItemQuery["projectWorkItem"]>;

export function statusBadgeClass(status: CoordinationPresentationStatus): string {
  return {
    PENDING: "text-bg-secondary",
    READY: "text-bg-info",
    ASSIGNED: "text-bg-warning",
    RUNNING: "text-bg-primary",
    COMPLETED: "text-bg-success"
  }[status];
}

export function resetPagination(params: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(params);
  next.delete("after");
  next.delete("trail");
  return next;
}

export function nextPageParams(params: URLSearchParams, nextCursor: string): URLSearchParams {
  const next = new URLSearchParams(params);
  next.append("trail", params.get("after") ?? PAGE_START);
  next.set("after", nextCursor);
  return next;
}

export function previousPageParams(params: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(params);
  const trail = next.getAll("trail");
  const previous = trail.pop();
  next.delete("trail");
  trail.forEach((cursor) => next.append("trail", cursor));
  if (!previous || previous === PAGE_START) next.delete("after");
  else next.set("after", previous);
  return next;
}

export function exactWorkItemFilterParams(
  params: URLSearchParams,
  changeSetId: string,
  agentId: string
): URLSearchParams {
  const next = resetPagination(params);
  const filters = { changeSet: changeSetId.trim(), agent: agentId.trim() };
  Object.entries(filters).forEach(([key, value]) => {
    if (value) next.set(key, value);
    else next.delete(key);
  });
  return next;
}

export function listLocation(pathname: string, params: URLSearchParams): string {
  const query = params.toString();
  return query ? `${pathname}?${query}` : pathname;
}

export function detailLocation(pathname: string, id: string, returnTo: string): string {
  const params = new URLSearchParams({ returnTo });
  return `${pathname}/${encodeURIComponent(id)}?${params.toString()}`;
}

export function safeReturnTo(value: string | null, expectedPath: string): string {
  return value === expectedPath || value?.startsWith(`${expectedPath}?`) ? value : expectedPath;
}
