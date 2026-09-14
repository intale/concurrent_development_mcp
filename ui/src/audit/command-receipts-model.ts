import type {
  AuditCommandReceiptQuery,
  AuditCommandReceiptsQuery,
  CommandReceiptStatus,
  LatestUpdateSort
} from "../gql/graphql.js";

export const COMMAND_RECEIPT_STATUSES: ReadonlyArray<{
  readonly label: string;
  readonly value: CommandReceiptStatus;
}> = [
  { label: "Completed successfully", value: "OK" }
];

export interface CommandReceiptFilters {
  readonly status?: CommandReceiptStatus;
  readonly toolName?: string;
  readonly sort: LatestUpdateSort;
}

export type CommandReceiptPage = AuditCommandReceiptsQuery["commandReceipts"];
export type CommandReceipt = NonNullable<AuditCommandReceiptQuery["commandReceipt"]>;

export function parseCommandReceiptStatus(value: string | null): CommandReceiptStatus | undefined {
  return value === "OK" ? "OK" : undefined;
}

export function preserveReceiptPage(
  previousData: AuditCommandReceiptsQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  toolName: string,
  status: CommandReceiptStatus | undefined,
  sort: LatestUpdateSort
): AuditCommandReceiptsQuery | undefined {
  return previousQueryKey?.[1] === toolName && previousQueryKey?.[2] === status && previousQueryKey?.[3] === sort
    ? previousData
    : undefined;
}

export function preserveReceiptDetail(
  previousData: AuditCommandReceiptQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  commandId: string
): AuditCommandReceiptQuery | undefined {
  return previousQueryKey?.[1] === commandId ? previousData : undefined;
}

export function nextReceiptPageParameters(
  current: URLSearchParams,
  endCursor: string
): URLSearchParams {
  const next = new URLSearchParams(current);
  next.append("trail", next.get("after") ?? "");
  next.set("after", endCursor);
  return next;
}

export function previousReceiptPageParameters(current: URLSearchParams): URLSearchParams {
  const previous = new URLSearchParams(current);
  const trail = previous.getAll("trail");
  const after = trail.pop();
  previous.delete("trail");
  trail.forEach((cursor) => previous.append("trail", cursor));
  if (after) previous.set("after", after);
  else previous.delete("after");
  return previous;
}

export function resetReceiptPagination(current: URLSearchParams): URLSearchParams {
  const reset = new URLSearchParams(current);
  reset.delete("after");
  reset.delete("trail");
  return reset;
}

export function formattedTimestamp(value: string): string {
  return new Date(value).toLocaleString();
}
