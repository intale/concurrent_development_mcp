import {
  ProjectDeliveryCandidateDocument,
  ProjectDeliveryCandidatesDocument,
  ProjectDeliveryMergeDocument,
  ProjectDeliveryMergesDocument,
  ProjectDeliveryObligationsDocument,
  ProjectDeliveryReleaseDocument,
  ProjectDeliveryReleasesDocument,
  ProjectDeliveryVerificationDocument
} from "../gql/graphql.js";
import type {
  CandidateCheckpointKind,
  CandidateImpactDirection,
  DeliverySort,
  ProjectDeliveryCandidateQuery,
  ProjectDeliveryCandidateQueryVariables,
  ProjectDeliveryCandidatesQuery,
  ProjectDeliveryCandidatesQueryVariables,
  ProjectDeliveryMergeQuery,
  ProjectDeliveryMergeQueryVariables,
  ProjectDeliveryMergesQuery,
  ProjectDeliveryMergesQueryVariables,
  ProjectDeliveryObligationsQuery,
  ProjectDeliveryObligationsQueryVariables,
  ProjectDeliveryReleaseQuery,
  ProjectDeliveryReleaseQueryVariables,
  ProjectDeliveryReleasesQuery,
  ProjectDeliveryReleasesQueryVariables,
  ProjectDeliveryVerificationQuery,
  ProjectDeliveryVerificationQueryVariables,
  ReleaseSetStatus,
  VerificationObligationStatus
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const DELIVERY_PAGE_SIZE = 20;

export interface CandidateFilters {
  readonly changeSetId?: string;
  readonly checkpointKind?: CandidateCheckpointKind;
  readonly sort: DeliverySort;
}

export interface ObligationFilters {
  readonly changeSetId?: string;
  readonly sort: DeliverySort;
  readonly status?: VerificationObligationStatus;
}

export interface ReleaseFilters {
  readonly changeSetId?: string;
  readonly sort: DeliverySort;
  readonly status?: ReleaseSetStatus;
}

export function fetchDeliveryCandidates(
  projectRef: string,
  filters: CandidateFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryCandidatesQuery> {
  const variables: ProjectDeliveryCandidatesQueryVariables = {
    projectRef,
    first: DELIVERY_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectDeliveryCandidatesDocument, variables, signal);
}

export function fetchDeliveryObligations(
  projectRef: string,
  filters: ObligationFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryObligationsQuery> {
  const variables: ProjectDeliveryObligationsQueryVariables = {
    projectRef,
    first: DELIVERY_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectDeliveryObligationsDocument, variables, signal);
}

export function fetchDeliveryMerges(
  projectRef: string,
  sort: DeliverySort,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryMergesQuery> {
  const variables: ProjectDeliveryMergesQueryVariables = {
    projectRef,
    first: DELIVERY_PAGE_SIZE,
    sort,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectDeliveryMergesDocument, variables, signal);
}

export function fetchDeliveryReleases(
  projectRef: string,
  filters: ReleaseFilters,
  after: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryReleasesQuery> {
  const variables: ProjectDeliveryReleasesQueryVariables = {
    projectRef,
    first: DELIVERY_PAGE_SIZE,
    ...filters,
    ...(after ? { after } : {})
  };
  return executeGraphql(ProjectDeliveryReleasesDocument, variables, signal);
}

export function fetchCandidate(
  projectRef: string,
  candidateId: string,
  direction: CandidateImpactDirection,
  impactsAfter: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryCandidateQuery> {
  const variables: ProjectDeliveryCandidateQueryVariables = {
    projectRef,
    candidateId,
    direction,
    first: DELIVERY_PAGE_SIZE,
    ...(impactsAfter ? { impactsAfter } : {})
  };
  return executeGraphql(ProjectDeliveryCandidateDocument, variables, signal);
}

export function fetchVerification(
  projectRef: string,
  obligationId: string,
  evidenceAfter: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryVerificationQuery> {
  const variables: ProjectDeliveryVerificationQueryVariables = {
    projectRef,
    obligationId,
    evidenceFirst: DELIVERY_PAGE_SIZE,
    ...(evidenceAfter ? { evidenceAfter } : {})
  };
  return executeGraphql(ProjectDeliveryVerificationDocument, variables, signal);
}

export function fetchMerge(
  projectRef: string,
  mergeSnapshotId: string,
  authorizationsAfter: string | null,
  signal?: AbortSignal
): Promise<ProjectDeliveryMergeQuery> {
  const variables: ProjectDeliveryMergeQueryVariables = {
    projectRef,
    mergeSnapshotId,
    authorizationsFirst: DELIVERY_PAGE_SIZE,
    ...(authorizationsAfter ? { authorizationsAfter } : {})
  };
  return executeGraphql(ProjectDeliveryMergeDocument, variables, signal);
}

export function fetchRelease(
  projectRef: string,
  releaseSetId: string,
  signal?: AbortSignal
): Promise<ProjectDeliveryReleaseQuery> {
  const variables: ProjectDeliveryReleaseQueryVariables = { projectRef, releaseSetId };
  return executeGraphql(ProjectDeliveryReleaseDocument, variables, signal);
}
