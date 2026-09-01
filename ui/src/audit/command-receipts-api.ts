import {
  AuditCommandReceiptDocument,
  AuditCommandReceiptsDocument
} from "../gql/graphql.js";
import type {
  AuditCommandReceiptQuery,
  AuditCommandReceiptQueryVariables,
  AuditCommandReceiptsQuery,
  AuditCommandReceiptsQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";
import type { CommandReceiptFilters } from "./command-receipts-model.js";

export const COMMAND_RECEIPT_PAGE_SIZE = 20;

export function fetchCommandReceipts(
  filters: CommandReceiptFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<AuditCommandReceiptsQuery> {
  const variables: AuditCommandReceiptsQueryVariables = {
    first: COMMAND_RECEIPT_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };

  return executeGraphql(AuditCommandReceiptsDocument, variables, signal);
}

export function fetchCommandReceipt(
  commandId: string,
  signal?: AbortSignal
): Promise<AuditCommandReceiptQuery> {
  const variables: AuditCommandReceiptQueryVariables = { commandId };
  return executeGraphql(AuditCommandReceiptDocument, variables, signal);
}
