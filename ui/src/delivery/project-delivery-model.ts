import type {
  CandidateCheckpointKind,
  CandidateImpactDirection,
  DeliverySort,
  ProjectDeliveryCandidateQuery,
  ProjectDeliveryMergeQuery,
  ProjectDeliveryQuery,
  ProjectDeliveryReleaseQuery,
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
export interface DeliveryFilters {
  readonly sort: DeliverySort;
  readonly candidateChangeSetId?: string;
  readonly candidateCheckpointKind?: CandidateCheckpointKind;
  readonly obligationChangeSetId?: string;
  readonly obligationStatus?: VerificationObligationStatus;
  readonly releaseChangeSetId?: string;
  readonly releaseStatus?: ReleaseSetStatus;
}

export interface DeliveryCursors {
  readonly afterCandidate?: string;
  readonly afterObligation?: string;
  readonly afterMergeSnapshot?: string;
  readonly afterReleaseSet?: string;
}

export type ProjectDelivery = NonNullable<ProjectDeliveryQuery["projectDelivery"]>;
export type CandidateDetail = NonNullable<ProjectDeliveryCandidateQuery["projectCandidateCheckpoint"]>;
export type VerificationDetail = NonNullable<ProjectDeliveryVerificationQuery["projectVerificationObligation"]>;
export type MergeDetail = NonNullable<ProjectDeliveryMergeQuery["projectMergeSnapshot"]>;
export type ReleaseDetail = NonNullable<ProjectDeliveryReleaseQuery["projectReleaseSet"]>;

export function preserveForProject<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string
): T | undefined {
  return previousQueryKey?.[1] === repositoryId ? previousData : undefined;
}

export function preserveForIdentity<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string,
  identity: string
): T | undefined {
  return previousQueryKey?.[1] === repositoryId && previousQueryKey?.[2] === identity
    ? previousData
    : undefined;
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

export function impactDirection(value: string | null): CandidateImpactDirection {
  return value === "INCOMING" ? "INCOMING" : "OUTGOING";
}
