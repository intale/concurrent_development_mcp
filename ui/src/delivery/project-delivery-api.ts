import {
  ProjectDeliveryCandidateDocument,
  ProjectDeliveryDocument,
  ProjectDeliveryMergeDocument,
  ProjectDeliveryReleaseDocument,
  ProjectDeliveryVerificationDocument
} from "../gql/graphql.js";
import type {
  CandidateImpactDirection,
  ProjectDeliveryCandidateQuery,
  ProjectDeliveryCandidateQueryVariables,
  ProjectDeliveryMergeQuery,
  ProjectDeliveryMergeQueryVariables,
  ProjectDeliveryQuery,
  ProjectDeliveryQueryVariables,
  ProjectDeliveryReleaseQuery,
  ProjectDeliveryReleaseQueryVariables,
  ProjectDeliveryVerificationQuery,
  ProjectDeliveryVerificationQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";
import type { DeliveryCursors, DeliveryFilters } from "./project-delivery-model.js";

export const DELIVERY_PAGE_SIZE = 20;

export function fetchProjectDelivery(
  repositoryId: string,
  filters: DeliveryFilters,
  cursors: DeliveryCursors,
  signal?: AbortSignal
): Promise<ProjectDeliveryQuery> {
  const variables: ProjectDeliveryQueryVariables = {
    repositoryId,
    first: DELIVERY_PAGE_SIZE,
    ...filters,
    ...cursors
  };
  return executeGraphql(ProjectDeliveryDocument, variables, signal);
}

export function fetchCandidate(
  repositoryId: string,
  candidateId: string,
  direction: CandidateImpactDirection,
  impactsAfter?: string,
  signal?: AbortSignal
): Promise<ProjectDeliveryCandidateQuery> {
  const variables: ProjectDeliveryCandidateQueryVariables = {
    repositoryId,
    candidateId,
    direction,
    first: DELIVERY_PAGE_SIZE,
    ...(impactsAfter ? { impactsAfter } : {})
  };
  return executeGraphql(ProjectDeliveryCandidateDocument, variables, signal);
}

export function fetchVerification(
  repositoryId: string,
  obligationId: string,
  evidenceAfter?: string,
  signal?: AbortSignal
): Promise<ProjectDeliveryVerificationQuery> {
  const variables: ProjectDeliveryVerificationQueryVariables = {
    repositoryId,
    obligationId,
    evidenceFirst: DELIVERY_PAGE_SIZE,
    ...(evidenceAfter ? { evidenceAfter } : {})
  };
  return executeGraphql(ProjectDeliveryVerificationDocument, variables, signal);
}

export function fetchMerge(
  repositoryId: string,
  mergeSnapshotId: string,
  authorizationsAfter?: string,
  signal?: AbortSignal
): Promise<ProjectDeliveryMergeQuery> {
  const variables: ProjectDeliveryMergeQueryVariables = {
    repositoryId,
    mergeSnapshotId,
    authorizationsFirst: DELIVERY_PAGE_SIZE,
    ...(authorizationsAfter ? { authorizationsAfter } : {})
  };
  return executeGraphql(ProjectDeliveryMergeDocument, variables, signal);
}

export function fetchRelease(
  repositoryId: string,
  releaseSetId: string,
  signal?: AbortSignal
): Promise<ProjectDeliveryReleaseQuery> {
  const variables: ProjectDeliveryReleaseQueryVariables = { repositoryId, releaseSetId };
  return executeGraphql(ProjectDeliveryReleaseDocument, variables, signal);
}
