import type {
  DeliverySort,
  OperationBatchStatus,
  OperationBatchTool,
  OperationsBatchQuery,
  OperationsBatchesQuery
} from "../gql/graphql.js";

export const OPERATION_BATCH_SORTS: ReadonlyArray<{
  readonly label: string;
  readonly value: DeliverySort;
}> = [
  { label: "Newest first", value: "NEWEST_FIRST" },
  { label: "Oldest first", value: "OLDEST_FIRST" }
];

export const OPERATION_BATCH_STATUSES: ReadonlyArray<{
  readonly label: string;
  readonly value: OperationBatchStatus;
}> = [
  { label: "Running", value: "RUNNING" },
  { label: "Cancelling", value: "CANCELLING" },
  { label: "Completed", value: "COMPLETED" },
  { label: "Completed with errors", value: "COMPLETED_WITH_ERRORS" },
  { label: "Cancelled", value: "CANCELLED" }
];

export const OPERATION_BATCH_TOOLS: ReadonlyArray<{
  readonly label: string;
  readonly value: OperationBatchTool;
}> = [
  { label: "Skill publish", value: "SKILL_PUBLISH" },
  { label: "Artifact capture", value: "DEVELOPMENT_ARTIFACT_CAPTURE" },
  { label: "Artifact relation", value: "DEVELOPMENT_ARTIFACT_RELATION_DECLARE" }
];

export interface OperationBatchFilters {
  readonly sort: DeliverySort;
  readonly status?: OperationBatchStatus;
  readonly targetTool?: OperationBatchTool;
}

export type OperationBatchPage = OperationsBatchesQuery["operationBatches"];
export type OperationBatch = NonNullable<OperationsBatchQuery["operationBatch"]>;

export function parseOperationBatchSort(value: string | null): DeliverySort {
  return value === "OLDEST_FIRST" ? "OLDEST_FIRST" : "NEWEST_FIRST";
}

export function parseOperationBatchStatus(value: string | null): OperationBatchStatus | undefined {
  return OPERATION_BATCH_STATUSES.some((option) => option.value === value)
    ? value as OperationBatchStatus
    : undefined;
}

export function parseOperationBatchTool(value: string | null): OperationBatchTool | undefined {
  return OPERATION_BATCH_TOOLS.some((option) => option.value === value)
    ? value as OperationBatchTool
    : undefined;
}

export function preserveBatchPage(
  previousData: OperationsBatchesQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  filters: OperationBatchFilters
): OperationsBatchesQuery | undefined {
  return previousQueryKey?.[1] === filters.sort &&
    previousQueryKey?.[2] === filters.status &&
    previousQueryKey?.[3] === filters.targetTool
    ? previousData
    : undefined;
}

export function preserveBatchDetail(
  previousData: OperationsBatchQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  batchId: string
): OperationsBatchQuery | undefined {
  return previousQueryKey?.[1] === batchId ? previousData : undefined;
}

export function nextBatchPageParameters(
  current: URLSearchParams,
  cursor: string,
  afterKey = "after",
  trailKey = "trail"
): URLSearchParams {
  const next = new URLSearchParams(current);
  next.append(trailKey, next.get(afterKey) ?? "");
  next.set(afterKey, cursor);
  return next;
}

export function previousBatchPageParameters(
  current: URLSearchParams,
  afterKey = "after",
  trailKey = "trail"
): URLSearchParams {
  const previous = new URLSearchParams(current);
  const trail = previous.getAll(trailKey);
  const after = trail.pop();
  previous.delete(trailKey);
  trail.forEach((cursor) => previous.append(trailKey, cursor));
  if (after) previous.set(afterKey, after);
  else previous.delete(afterKey);
  return previous;
}

export function resetBatchPagination(current: URLSearchParams): URLSearchParams {
  const reset = new URLSearchParams(current);
  reset.delete("after");
  reset.delete("trail");
  return reset;
}

export function batchStatusClass(status: string): string {
  switch (status.toLowerCase()) {
    case "completed":
    case "succeeded":
      return "text-bg-success";
    case "completed_with_errors":
    case "rejected":
      return "text-bg-danger";
    case "running":
      return "text-bg-primary";
    case "cancelling":
      return "text-bg-warning";
    default:
      return "text-bg-secondary";
  }
}

export function humanizedOperation(value: string): string {
  return value.toLowerCase().replaceAll("_", " ");
}

export function formattedTimestamp(value: string | null): string {
  return value ? new Date(value).toLocaleString() : "Not finished";
}
