import type {
  CoordinationPresentationStatus,
  ProjectCoordinationQuery,
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

export type CoordinationDashboard = NonNullable<ProjectCoordinationQuery["projectCoordination"]>;
export type CoordinationWorkItem = CoordinationDashboard["workItems"]["nodes"][number];

export function preserveDashboardForProject(
  previousData: ProjectCoordinationQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string
): ProjectCoordinationQuery | undefined {
  return previousQueryKey?.[1] === repositoryId ? previousData : undefined;
}

export function statusBadgeClass(status: CoordinationPresentationStatus): string {
  return {
    PENDING: "text-bg-secondary",
    READY: "text-bg-info",
    ASSIGNED: "text-bg-warning",
    RUNNING: "text-bg-primary",
    COMPLETED: "text-bg-success"
  }[status];
}
