import type {
  CandidateCheckpointKind,
  CandidateImpactDirection,
  DeliverySort,
  ProjectDeliveryCandidateQuery,
  ProjectDeliveryCandidatesQuery,
  ProjectDeliveryMergeQuery,
  ProjectDeliveryMergesQuery,
  ProjectDeliveryObligationsQuery,
  ProjectDeliveryReleaseQuery,
  ProjectDeliveryReleasesQuery,
  ProjectDeliveryVerificationQuery,
  ReleaseSetStatus,
  VerificationObligationStatus
} from "../gql/graphql.js";

export const DELIVERY_SORTS: ReadonlyArray<{ readonly label: string; readonly value: DeliverySort }> = [
  { label: "Newest first", value: "NEWEST_FIRST" },
  { label: "Oldest first", value: "OLDEST_FIRST" }
];
export const CHECKPOINT_KINDS: ReadonlyArray<{ readonly label: string; readonly value: CandidateCheckpointKind }> = [
  { label: "Intermediate", value: "INTERMEDIATE" },
  { label: "Handoff", value: "HANDOFF" },
  { label: "Final", value: "FINAL" }
];
export const OBLIGATION_STATUSES: ReadonlyArray<{ readonly label: string; readonly value: VerificationObligationStatus }> = [
  { label: "Open", value: "OPEN" },
  { label: "Satisfied", value: "SATISFIED" },
  { label: "Failed", value: "FAILED" },
  { label: "Waived", value: "WAIVED" },
  { label: "Invalidated", value: "INVALIDATED" }
];
export const RELEASE_STATUSES: ReadonlyArray<{ readonly label: string; readonly value: ReleaseSetStatus }> = [
  { label: "Prepared", value: "PREPARED" },
  { label: "Integrating", value: "INTEGRATING" },
  { label: "Verifying", value: "VERIFYING" },
  { label: "Verified", value: "VERIFIED" },
  { label: "Activated", value: "ACTIVATED" },
  { label: "Compensation requested", value: "COMPENSATION_REQUESTED" },
  { label: "Completed", value: "COMPLETED" }
];

export type CandidateConnection = NonNullable<ProjectDeliveryCandidatesQuery["projectCandidateCheckpoints"]>;
export type ObligationConnection = NonNullable<ProjectDeliveryObligationsQuery["projectVerificationObligations"]>;
export type MergeConnection = NonNullable<ProjectDeliveryMergesQuery["projectMergeSnapshots"]>;
export type ReleaseConnection = NonNullable<ProjectDeliveryReleasesQuery["projectReleaseSets"]>;
export type CandidateDetail = NonNullable<ProjectDeliveryCandidateQuery["projectCandidateCheckpoint"]>;
export type VerificationDetail = NonNullable<ProjectDeliveryVerificationQuery["projectVerificationObligation"]>;
export type MergeDetail = NonNullable<ProjectDeliveryMergeQuery["projectMergeSnapshot"]>;
export type ReleaseDetail = NonNullable<ProjectDeliveryReleaseQuery["projectReleaseSet"]>;

export function matching<T extends string>(
  requested: string | null,
  options: ReadonlyArray<{ readonly value: T }>
): T | undefined {
  return options.find(({ value }) => value === requested)?.value;
}

export function impactDirection(value: string | null): CandidateImpactDirection {
  return value === "INCOMING" ? "INCOMING" : "OUTGOING";
}

export function preserveCollection<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  filterKey: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === filterKey ? previousData : undefined;
}

export function preserveDetail<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  identity: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === identity ? previousData : undefined;
}

export function applyFilters(
  current: URLSearchParams,
  changes: Readonly<Record<string, string>>
): URLSearchParams {
  const next = new URLSearchParams(current);
  Object.entries(changes).forEach(([key, value]) => value ? next.set(key, value) : next.delete(key));
  next.delete("after");
  next.delete("trail");
  return next;
}

export function nextPageParams(current: URLSearchParams, cursor: string): URLSearchParams {
  const next = new URLSearchParams(current);
  const currentCursor = current.get("after");
  next.append("trail", currentCursor ?? "");
  next.set("after", cursor);
  return next;
}

export function previousPageParams(current: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(current);
  const trail = current.getAll("trail");
  const previous = trail.pop();
  next.delete("trail");
  trail.forEach((cursor) => next.append("trail", cursor));
  if (previous) next.set("after", previous); else next.delete("after");
  return next;
}

export function listLocation(path: string, searchParams: URLSearchParams): string {
  const query = searchParams.toString();
  return query ? `${path}?${query}` : path;
}

export function detailLocation(path: string, id: string, returnTo: string): string {
  return `${path}/${encodeURIComponent(id)}?${new URLSearchParams({ returnTo }).toString()}`;
}

export function safeDeliveryReturnTo(value: string | null, fallback: string, basePath: string): string {
  if (!value) return fallback;
  try {
    const parsed = new URL(value, "http://coordinator.local");
    return parsed.origin === "http://coordinator.local" && parsed.pathname.startsWith(`${basePath}/`)
      ? `${parsed.pathname}${parsed.search}`
      : fallback;
  } catch {
    return fallback;
  }
}

export function humanized(value: string): string {
  return value.toLowerCase().replaceAll("_", " ").replaceAll(".", " · ");
}

export function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}

export function badgeClass(status: string): string {
  switch (status.toLowerCase()) {
    case "satisfied":
    case "verified":
    case "activated":
    case "completed":
    case "succeeded":
    case "granted":
      return "text-bg-success";
    case "failed":
    case "rejected":
    case "invalidated":
    case "denied":
    case "completed_with_errors":
      return "text-bg-danger";
    case "open":
    case "running":
    case "integrating":
      return "text-bg-primary";
    case "cancelling":
    case "verifying":
    case "compensation_requested":
      return "text-bg-warning";
    default:
      return "text-bg-secondary";
  }
}
