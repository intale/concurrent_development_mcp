import { OperationsBatchDocument, OperationsBatchesDocument } from "../gql/graphql.js";
import type {
  OperationsBatchQuery,
  OperationsBatchQueryVariables,
  OperationsBatchesQuery,
  OperationsBatchesQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";
import type { OperationBatchFilters } from "./operation-batches-model.js";

export const OPERATION_BATCH_PAGE_SIZE = 20;

export function fetchOperationBatches(
  filters: OperationBatchFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<OperationsBatchesQuery> {
  const variables: OperationsBatchesQueryVariables = {
    first: OPERATION_BATCH_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(OperationsBatchesDocument, variables, signal);
}

export function fetchOperationBatch(
  batchId: string,
  itemsAfter: string | null,
  signal?: AbortSignal
): Promise<OperationsBatchQuery> {
  const variables: OperationsBatchQueryVariables = {
    batchId,
    first: OPERATION_BATCH_PAGE_SIZE,
    ...(itemsAfter ? { itemsAfter } : {})
  };
  return executeGraphql(OperationsBatchDocument, variables, signal);
}
