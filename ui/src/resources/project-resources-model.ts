import type {
  ProjectActiveResourceWorkIntentionsQuery,
  ProjectResourceFieldsFragment,
  ProjectResourceWorkIntentionQuery,
  ProjectResourceQuery,
  ProjectResourcesQuery,
  ResourceKind,
  ResourceWorkIntentionFieldsFragment,
  ResourceWorkIntentionMode,
  ResourceWorkIntentionStatus,
  ResourceLifecycleStatus
} from "../gql/graphql.js";

export const RESOURCE_KINDS: ReadonlyArray<{ readonly label: string; readonly value: ResourceKind }> = [
  { label: "Files", value: "FILE" },
  { label: "Directories", value: "DIRECTORY" }
];

export const RESOURCE_LIFECYCLE_STATUSES: ReadonlyArray<{
  readonly label: string;
  readonly value: ResourceLifecycleStatus;
}> = [
  { label: "Registered", value: "REGISTERED" },
  { label: "Current", value: "CURRENT" },
  { label: "Inactive", value: "INACTIVE" }
];

export const WORK_INTENTION_MODES: ReadonlyArray<{
  readonly label: string;
  readonly value: ResourceWorkIntentionMode;
}> = [
  { label: "Shared", value: "SHARED" },
  { label: "Exclusive", value: "EXCLUSIVE" }
];

export const PAGE_START = "__resource_page_start__";

export type ProjectResource = ProjectResourceFieldsFragment;
export type ResourceWorkIntention = ResourceWorkIntentionFieldsFragment;
export type ProjectResourceConnection = NonNullable<ProjectResourcesQuery["projectResources"]>;
export type ProjectResourceDetail = NonNullable<ProjectResourceQuery["projectResource"]>;
export type ResourceWorkIntentionConnection = NonNullable<
  ProjectActiveResourceWorkIntentionsQuery["projectActiveResourceWorkIntentions"]
>;
export type ResourceWorkIntentionDetail = NonNullable<
  ProjectResourceWorkIntentionQuery["projectResourceWorkIntention"]
>;

export function lifecycleBadgeClass(status: ResourceLifecycleStatus): string {
  return {
    REGISTERED: "text-bg-info",
    CURRENT: "text-bg-success",
    INACTIVE: "text-bg-secondary"
  }[status];
}

export function workIntentionBadgeClass(status: ResourceWorkIntentionStatus): string {
  return {
    ACTIVE: "text-bg-warning",
    EXPIRED: "text-bg-secondary",
    WITHDRAWN: "text-bg-success",
    ATTEMPT_TERMINAL: "text-bg-dark"
  }[status];
}

export function preserveCollection<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  filterKey: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === filterKey
    ? previousData
    : undefined;
}

export function preserveDetail<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  identity: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === identity
    ? previousData
    : undefined;
}

export function resetPagination(params: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(params);
  next.delete("after");
  next.delete("trail");
  return next;
}

export function nextPageParams(params: URLSearchParams, cursor: string): URLSearchParams {
  const next = new URLSearchParams(params);
  next.append("trail", params.get("after") ?? PAGE_START);
  next.set("after", cursor);
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

export function applyFilters(
  params: URLSearchParams,
  filters: Readonly<Record<string, string>>
): URLSearchParams {
  const next = resetPagination(params);
  Object.entries(filters).forEach(([key, value]) => {
    const normalized = value.trim();
    if (normalized) next.set(key, normalized);
    else next.delete(key);
  });
  return next;
}

export function listLocation(pathname: string, params: URLSearchParams): string {
  const query = params.toString();
  return query ? `${pathname}?${query}` : pathname;
}

export function detailLocation(pathname: string, id: string, returnTo: string): string {
  return `${pathname}/${encodeURIComponent(id)}?${new URLSearchParams({ returnTo }).toString()}`;
}

export function safeReturnTo(value: string | null, expectedPath: string): string {
  return value === expectedPath || value?.startsWith(`${expectedPath}?`) ? value : expectedPath;
}
