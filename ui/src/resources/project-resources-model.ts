import type {
  ProjectResourcesQuery,
  ResourceKind,
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

export type ProjectResourceBrowser = NonNullable<ProjectResourcesQuery["projectResources"]>;

export function preserveResourcesForProject(
  previousData: ProjectResourcesQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string
): ProjectResourcesQuery | undefined {
  return previousQueryKey?.[1] === repositoryId ? previousData : undefined;
}

export function lifecycleBadgeClass(status: ResourceLifecycleStatus): string {
  return {
    REGISTERED: "text-bg-info",
    CURRENT: "text-bg-success",
    INACTIVE: "text-bg-secondary"
  }[status];
}
