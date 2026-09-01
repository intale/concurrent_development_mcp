import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type {
  CandidateCheckpointKind,
  DeliverySort,
  ReleaseSetStatus,
  VerificationObligationStatus
} from "../gql/graphql.js";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import {
  fetchCandidate,
  fetchDeliveryCandidates,
  fetchDeliveryMerges,
  fetchDeliveryObligations,
  fetchDeliveryReleases,
  fetchMerge,
  fetchRelease,
  fetchVerification
} from "./project-delivery-api.js";
import type { CandidateFilters, ObligationFilters, ReleaseFilters } from "./project-delivery-api.js";
import {
  applyFilters,
  CHECKPOINT_KINDS,
  DELIVERY_SORTS,
  detailLocation,
  impactDirection,
  listLocation,
  matching,
  nextPageParams,
  OBLIGATION_STATUSES,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  RELEASE_STATUSES,
  safeDeliveryReturnTo
} from "./project-delivery-model.js";
import {
  AvailableStale,
  CandidateCards,
  CandidateDetailCard,
  DeliveryNavigation,
  InitialError,
  LoadingState,
  MergeCards,
  MergeDetailCard,
  ObligationCards,
  PageHeading,
  PaginationControls,
  ReleaseCards,
  ReleaseDetailCard,
  useDeliveryHeading,
  VerificationDetailCard
} from "./project-delivery-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectDeliveryCandidatesPage() {
  const { projectRef } = useProjectWorkspace();
  const { candidateId } = useParams<{ readonly candidateId?: string }>();
  return candidateId ? <CandidatePage candidateId={candidateId} projectRef={projectRef} /> : <CandidatesPage projectRef={projectRef} />;
}

export function ProjectDeliveryObligationsPage() {
  const { projectRef } = useProjectWorkspace();
  const { obligationId } = useParams<{ readonly obligationId?: string }>();
  return obligationId ? <ObligationPage obligationId={obligationId} projectRef={projectRef} /> : <ObligationsPage projectRef={projectRef} />;
}

export function ProjectDeliveryMergesPage() {
  const { projectRef } = useProjectWorkspace();
  const { mergeSnapshotId } = useParams<{ readonly mergeSnapshotId?: string }>();
  return mergeSnapshotId ? <MergePage mergeSnapshotId={mergeSnapshotId} projectRef={projectRef} /> : <MergesPage projectRef={projectRef} />;
}

export function ProjectDeliveryReleasesPage() {
  const { projectRef } = useProjectWorkspace();
  const { releaseSetId } = useParams<{ readonly releaseSetId?: string }>();
  return releaseSetId ? <ReleasePage projectRef={projectRef} releaseSetId={releaseSetId} /> : <ReleasesPage projectRef={projectRef} />;
}

function CandidatesPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const listPath = `${basePath}/candidates`;
  const sort = matching<DeliverySort>(searchParams.get("sort"), DELIVERY_SORTS) ?? "NEWEST_FIRST";
  const checkpointKind = matching<CandidateCheckpointKind>(searchParams.get("kind"), CHECKPOINT_KINDS);
  const changeSetId = searchParams.get("changeSet") ?? "";
  const [draft, setDraft] = useState({ changeSet: changeSetId, kind: checkpointKind ?? "", sort });
  const after = searchParams.get("after");
  const headingRef = useDeliveryHeading("Project Candidate checkpoints", "delivery-candidates");
  useEffect(() => { setDraft({ changeSet: changeSetId, kind: checkpointKind ?? "", sort }); }, [changeSetId, checkpointKind, sort]);
  const filters: CandidateFilters = { sort, ...(changeSetId ? { changeSetId } : {}), ...(checkpointKind ? { checkpointKind } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-delivery-candidates", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchDeliveryCandidates(projectRef, filters, after, signal),
    placeholderData: (data, previous) => preserveCollection(data, previous?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectCandidateCheckpoints ?? null;
  return <CollectionPage basePath={basePath} connection={connection} error={query.error} headingRef={headingRef} label="Candidate checkpoints" loading={query.isPending} retry={() => { void query.refetch(); }}><form aria-label="Candidate filters" className="card card-body" onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}><div className="row g-3 align-items-end"><div className="col-12 col-xl-5"><label className="form-label" htmlFor="candidate-change-set">ChangeSet</label><input className="form-control" id="candidate-change-set" onChange={(event) => setDraft((value) => ({ ...value, changeSet: event.target.value }))} placeholder="Exact ChangeSet ID" value={draft.changeSet} /></div><div className="col-12 col-sm-6 col-xl-2"><label className="form-label" htmlFor="candidate-kind">Kind</label><select className="form-select" id="candidate-kind" onChange={(event) => setDraft((value) => ({ ...value, kind: event.target.value as CandidateCheckpointKind | "" }))} value={draft.kind}><option value="">All kinds</option>{CHECKPOINT_KINDS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div><SortControl id="candidate-sort" onChange={(value) => setDraft((current) => ({ ...current, sort: value }))} value={draft.sort} /><FilterActions clear={() => setSearchParams({})} /></div></form>{connection ? <><CandidateCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PageControls connection={connection} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</CollectionPage>;
}

function ObligationsPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const listPath = `${basePath}/obligations`;
  const sort = matching<DeliverySort>(searchParams.get("sort"), DELIVERY_SORTS) ?? "NEWEST_FIRST";
  const status = matching<VerificationObligationStatus>(searchParams.get("status"), OBLIGATION_STATUSES);
  const changeSetId = searchParams.get("changeSet") ?? "";
  const [draft, setDraft] = useState({ changeSet: changeSetId, sort, status: status ?? "" });
  const after = searchParams.get("after");
  const headingRef = useDeliveryHeading("Project verification obligations", "delivery-obligations");
  useEffect(() => { setDraft({ changeSet: changeSetId, sort, status: status ?? "" }); }, [changeSetId, sort, status]);
  const filters: ObligationFilters = { sort, ...(changeSetId ? { changeSetId } : {}), ...(status ? { status } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({ queryKey: ["project-delivery-obligations", projectRef, filterKey, after], queryFn: ({ signal }) => fetchDeliveryObligations(projectRef, filters, after, signal), placeholderData: (data, previous) => preserveCollection(data, previous?.queryKey, projectRef, filterKey), refetchInterval: REFRESH_INTERVAL_MS });
  const connection = query.data?.projectVerificationObligations ?? null;
  return <CollectionPage basePath={basePath} connection={connection} error={query.error} headingRef={headingRef} label="Verification obligations" loading={query.isPending} retry={() => { void query.refetch(); }}><form aria-label="Obligation filters" className="card card-body" onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}><div className="row g-3 align-items-end"><div className="col-12 col-xl-5"><label className="form-label" htmlFor="obligation-change-set">ChangeSet</label><input className="form-control" id="obligation-change-set" onChange={(event) => setDraft((value) => ({ ...value, changeSet: event.target.value }))} placeholder="Exact ChangeSet ID" value={draft.changeSet} /></div><div className="col-12 col-sm-6 col-xl-2"><label className="form-label" htmlFor="obligation-status">Status</label><select className="form-select" id="obligation-status" onChange={(event) => setDraft((value) => ({ ...value, status: event.target.value as VerificationObligationStatus | "" }))} value={draft.status}><option value="">All statuses</option>{OBLIGATION_STATUSES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div><SortControl id="obligation-sort" onChange={(value) => setDraft((current) => ({ ...current, sort: value }))} value={draft.sort} /><FilterActions clear={() => setSearchParams({})} /></div></form>{connection ? <><ObligationCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PageControls connection={connection} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</CollectionPage>;
}

function MergesPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const listPath = `${basePath}/merge-snapshots`;
  const sort = matching<DeliverySort>(searchParams.get("sort"), DELIVERY_SORTS) ?? "NEWEST_FIRST";
  const after = searchParams.get("after");
  const headingRef = useDeliveryHeading("Project merge snapshots", "delivery-merges");
  const filterKey = JSON.stringify({ sort });
  const query = useQuery({ queryKey: ["project-delivery-merges", projectRef, filterKey, after], queryFn: ({ signal }) => fetchDeliveryMerges(projectRef, sort, after, signal), placeholderData: (data, previous) => preserveCollection(data, previous?.queryKey, projectRef, filterKey), refetchInterval: REFRESH_INTERVAL_MS });
  const connection = query.data?.projectMergeSnapshots ?? null;
  return <CollectionPage basePath={basePath} connection={connection} error={query.error} headingRef={headingRef} label="Merge snapshots" loading={query.isPending} retry={() => { void query.refetch(); }}><form aria-label="Merge snapshot filters" className="card card-body"><div className="row g-3 align-items-end"><SortControl id="merge-sort" onChange={(value) => setSearchParams(applyFilters(searchParams, { sort: value }))} value={sort} /><div className="col-12 col-sm-6 col-xl-3"><button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Reset</button></div></div></form>{connection ? <><MergeCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PageControls connection={connection} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</CollectionPage>;
}

function ReleasesPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const listPath = `${basePath}/release-sets`;
  const sort = matching<DeliverySort>(searchParams.get("sort"), DELIVERY_SORTS) ?? "NEWEST_FIRST";
  const status = matching<ReleaseSetStatus>(searchParams.get("status"), RELEASE_STATUSES);
  const changeSetId = searchParams.get("changeSet") ?? "";
  const [draft, setDraft] = useState({ changeSet: changeSetId, sort, status: status ?? "" });
  const after = searchParams.get("after");
  const headingRef = useDeliveryHeading("Project ReleaseSets", "delivery-release-sets");
  useEffect(() => { setDraft({ changeSet: changeSetId, sort, status: status ?? "" }); }, [changeSetId, sort, status]);
  const filters: ReleaseFilters = { sort, ...(changeSetId ? { changeSetId } : {}), ...(status ? { status } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({ queryKey: ["project-delivery-releases", projectRef, filterKey, after], queryFn: ({ signal }) => fetchDeliveryReleases(projectRef, filters, after, signal), placeholderData: (data, previous) => preserveCollection(data, previous?.queryKey, projectRef, filterKey), refetchInterval: REFRESH_INTERVAL_MS });
  const connection = query.data?.projectReleaseSets ?? null;
  return <CollectionPage basePath={basePath} connection={connection} error={query.error} headingRef={headingRef} label="ReleaseSets" loading={query.isPending} retry={() => { void query.refetch(); }}><form aria-label="ReleaseSet filters" className="card card-body" onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}><div className="row g-3 align-items-end"><div className="col-12 col-xl-5"><label className="form-label" htmlFor="release-change-set">ChangeSet</label><input className="form-control" id="release-change-set" onChange={(event) => setDraft((value) => ({ ...value, changeSet: event.target.value }))} placeholder="Exact ChangeSet ID" value={draft.changeSet} /></div><div className="col-12 col-sm-6 col-xl-2"><label className="form-label" htmlFor="release-status">Status</label><select className="form-select" id="release-status" onChange={(event) => setDraft((value) => ({ ...value, status: event.target.value as ReleaseSetStatus | "" }))} value={draft.status}><option value="">All statuses</option>{RELEASE_STATUSES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div><SortControl id="release-sort" onChange={(value) => setDraft((current) => ({ ...current, sort: value }))} value={draft.sort} /><FilterActions clear={() => setSearchParams({})} /></div></form>{connection ? <><ReleaseCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PageControls connection={connection} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</CollectionPage>;
}

function CandidatePage({ projectRef, candidateId }: { readonly projectRef: string; readonly candidateId: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const listPath = `${basePath}/candidates`;
  const backTo = safeDeliveryReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const direction = impactDirection(searchParams.get("direction"));
  const after = searchParams.get("after");
  const identity = `${candidateId}:${direction}`;
  const headingRef = useDeliveryHeading("Candidate checkpoint detail", candidateId);
  const query = useQuery({ queryKey: ["project-delivery-candidate", projectRef, identity, after], queryFn: ({ signal }) => fetchCandidate(projectRef, candidateId, direction, after, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, identity), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectCandidateCheckpoint ?? null;
  return <DetailPage backLabel="Candidates" backTo={backTo} basePath={basePath} detail={detail} error={query.error} headingRef={headingRef} label="Candidate checkpoint detail" loading={query.isPending} retry={() => { void query.refetch(); }}><form aria-label="Impact direction" className="card card-body"><label className="form-label" htmlFor="impact-direction">Potential impact direction</label><select className="form-select" id="impact-direction" onChange={(event) => setSearchParams(applyFilters(searchParams, { direction: event.target.value }))} value={direction}><option value="OUTGOING">Outgoing</option><option value="INCOMING">Incoming</option></select></form>{detail ? <><CandidateDetailCard detail={detail} /><PageControls connection={detail.impactRelationships} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</DetailPage>;
}

function ObligationPage({ projectRef, obligationId }: { readonly projectRef: string; readonly obligationId: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const backTo = safeDeliveryReturnTo(searchParams.get("returnTo"), `${basePath}/obligations`, basePath);
  const after = searchParams.get("after");
  const headingRef = useDeliveryHeading("Verification obligation detail", obligationId);
  const query = useQuery({ queryKey: ["project-delivery-obligation", projectRef, obligationId, after], queryFn: ({ signal }) => fetchVerification(projectRef, obligationId, after, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, obligationId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectVerificationObligation ?? null;
  return <DetailPage backLabel="Obligations" backTo={backTo} basePath={basePath} detail={detail} error={query.error} headingRef={headingRef} label="Verification obligation detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <><VerificationDetailCard detail={detail} /><PageControls connection={detail.evidence} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</DetailPage>;
}

function MergePage({ projectRef, mergeSnapshotId }: { readonly projectRef: string; readonly mergeSnapshotId: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const backTo = safeDeliveryReturnTo(searchParams.get("returnTo"), `${basePath}/merge-snapshots`, basePath);
  const after = searchParams.get("after");
  const headingRef = useDeliveryHeading("Merge snapshot detail", mergeSnapshotId);
  const query = useQuery({ queryKey: ["project-delivery-merge", projectRef, mergeSnapshotId, after], queryFn: ({ signal }) => fetchMerge(projectRef, mergeSnapshotId, after, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, mergeSnapshotId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectMergeSnapshot ?? null;
  return <DetailPage backLabel="Merge snapshots" backTo={backTo} basePath={basePath} detail={detail} error={query.error} headingRef={headingRef} label="Merge snapshot detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <><MergeDetailCard detail={detail} /><PageControls connection={detail.authorizations} searchParams={searchParams} setSearchParams={setSearchParams} /></> : null}</DetailPage>;
}

function ReleasePage({ projectRef, releaseSetId }: { readonly projectRef: string; readonly releaseSetId: string }) {
  const [searchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/delivery`;
  const backTo = safeDeliveryReturnTo(searchParams.get("returnTo"), `${basePath}/release-sets`, basePath);
  const headingRef = useDeliveryHeading("ReleaseSet detail", releaseSetId);
  const query = useQuery({ queryKey: ["project-delivery-release", projectRef, releaseSetId], queryFn: ({ signal }) => fetchRelease(projectRef, releaseSetId, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, releaseSetId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectReleaseSet ?? null;
  return <DetailPage backLabel="ReleaseSets" backTo={backTo} basePath={basePath} detail={detail} error={query.error} headingRef={headingRef} label="ReleaseSet detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <ReleaseDetailCard detail={detail} /> : null}</DetailPage>;
}

function CollectionPage({ basePath, children, connection, error, headingRef, label, loading, retry }: {
  readonly basePath: string;
  readonly children: React.ReactNode;
  readonly connection: unknown;
  readonly error: Error | null;
  readonly headingRef: React.RefObject<HTMLHeadingElement>;
  readonly label: string;
  readonly loading: boolean;
  readonly retry: () => void;
}) {
  const message = error instanceof Error ? error.message : null;
  return <div className="vstack gap-3"><DeliveryNavigation basePath={basePath} /><PageHeading description={`Browse the latest available ${label.toLowerCase()} for every Repository member of this exact Project.`} headingRef={headingRef} title={label} />{loading ? <LoadingState label={label} /> : null}{message && !connection ? <InitialError label={label} message={message} onRetry={retry} /> : null}{!loading && !message && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}{connection ? <>{message ? <AvailableStale message={message} onRetry={retry} /> : null}{children}</> : null}</div>;
}

function DetailPage({ backLabel, backTo, basePath, children, detail, error, headingRef, label, loading, retry }: {
  readonly backLabel: string;
  readonly backTo: string;
  readonly basePath: string;
  readonly children: React.ReactNode;
  readonly detail: unknown;
  readonly error: Error | null;
  readonly headingRef: React.RefObject<HTMLHeadingElement>;
  readonly label: string;
  readonly loading: boolean;
  readonly retry: () => void;
}) {
  const message = error instanceof Error ? error.message : null;
  return <div className="vstack gap-3"><DeliveryNavigation basePath={basePath} /><div><Link className="btn btn-outline-secondary mb-3" to={backTo}>← Back to {backLabel}</Link><PageHeading description="Inspect one focused delivery fact and its bounded supporting evidence." headingRef={headingRef} title={label} /></div>{loading ? <LoadingState label={label} /> : null}{message && !detail ? <InitialError label={label} message={message} onRetry={retry} /> : null}{!loading && !message && !detail ? <div className="alert alert-info" role="status">This item is not available inside the Project.</div> : null}{detail ? <>{message ? <AvailableStale message={message} onRetry={retry} /> : null}{children}</> : null}</div>;
}

function SortControl({ id, onChange, value }: { readonly id: string; readonly onChange: (value: DeliverySort) => void; readonly value: DeliverySort }) {
  return <div className="col-12 col-sm-6 col-xl-2"><label className="form-label" htmlFor={id}>Order</label><select className="form-select" id={id} onChange={(event) => onChange(event.target.value as DeliverySort)} value={value}>{DELIVERY_SORTS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>;
}

function FilterActions({ clear }: { readonly clear: () => void }) {
  return <div className="col-12 col-xl-3 d-flex gap-2"><button className="btn btn-primary" type="submit">Apply</button><button className="btn btn-outline-secondary" onClick={clear} type="button">Clear</button></div>;
}

function PageControls({ connection, searchParams, setSearchParams }: {
  readonly connection: { readonly pageInfo: { readonly endCursor: string | null; readonly hasNextPage: boolean } };
  readonly searchParams: URLSearchParams;
  readonly setSearchParams: (value: URLSearchParams) => void;
}) {
  return <PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} />;
}
