import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type { ResourceKind, ResourceLifecycleStatus } from "../gql/graphql.js";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import {
  fetchProjectActiveResourceLeases,
  fetchProjectResource,
  fetchProjectResourceLease,
  fetchProjectResources
} from "./project-resources-api.js";
import type { LeaseFilters, ResourceFilters } from "./project-resources-api.js";
import {
  applyFilters,
  detailLocation,
  listLocation,
  nextPageParams,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  RESOURCE_KINDS,
  RESOURCE_LIFECYCLE_STATUSES,
  safeReturnTo
} from "./project-resources-model.js";
import {
  AvailableStale,
  InitialError,
  LeaseCards,
  LeaseDetail,
  LoadingState,
  PaginationControls,
  ResourceCards,
  ResourceDetail,
  ResourceNavigation,
  useResourceHeading
} from "./project-resources-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectResourceInventoryPage() {
  const { projectRef } = useProjectWorkspace();
  const { resourceId } = useParams<{ resourceId?: string }>();

  return resourceId
    ? <ResourceDetailPage projectRef={projectRef} resourceId={resourceId} />
    : <ResourceInventoryPage projectRef={projectRef} />;
}

export function ProjectResourceLeasesPage() {
  const { projectRef } = useProjectWorkspace();
  const { leaseId } = useParams<{ leaseId?: string }>();

  return leaseId
    ? <LeaseDetailPage projectRef={projectRef} leaseId={leaseId} />
    : <ActiveLeasePage projectRef={projectRef} />;
}

function ResourceInventoryPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/inventory`;
  const sectionPath = `/projects/${projectRef}/resources`;
  const path = searchParams.get("path") ?? "";
  const resourceKind = validResourceKind(searchParams.get("kind"));
  const lifecycle = validLifecycle(searchParams.get("lifecycle"));
  const after = searchParams.get("after");
  const [draftPath, setDraftPath] = useState(path);
  const [draftKind, setDraftKind] = useState<ResourceKind | "">(resourceKind ?? "");
  const [draftLifecycle, setDraftLifecycle] = useState<ResourceLifecycleStatus | "">(lifecycle ?? "");
  const headingRef = useResourceHeading("Resource inventory", "resource-inventory");

  useEffect(() => {
    setDraftPath(path);
    setDraftKind(resourceKind ?? "");
    setDraftLifecycle(lifecycle ?? "");
  }, [path, resourceKind, lifecycle]);

  const filters: ResourceFilters = {
    ...(path ? { path } : {}),
    ...(resourceKind ? { resourceKind } : {}),
    ...(lifecycle ? { resourceLifecycleStatus: lifecycle } : {})
  };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-resources", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchProjectResources(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      filterKey
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectResources ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  const apply = () => setSearchParams(applyFilters(searchParams, {
    path: draftPath,
    kind: draftKind,
    lifecycle: draftLifecycle
  }));

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={sectionPath} />
      <div>
        <h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Resource inventory</h2>
        <p className="text-body-secondary mb-0">Find files and directories across every Repository in this exact Project.</p>
      </div>
      <form
        aria-label="Resource filters"
        className="card card-body"
        onSubmit={(event) => { event.preventDefault(); apply(); }}
      >
        <div className="row g-3 align-items-end">
          <div className="col-12 col-lg-6">
            <label className="form-label" htmlFor="resource-path">Path contains</label>
            <input className="form-control" id="resource-path" onChange={(event) => setDraftPath(event.target.value)} value={draftPath} />
          </div>
          <div className="col-12 col-sm-6 col-lg-2">
            <label className="form-label" htmlFor="resource-kind">Kind</label>
            <select className="form-select" id="resource-kind" onChange={(event) => setDraftKind(event.target.value as ResourceKind | "")} value={draftKind}>
              <option value="">All kinds</option>
              {RESOURCE_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}
            </select>
          </div>
          <div className="col-12 col-sm-6 col-lg-2">
            <label className="form-label" htmlFor="resource-lifecycle">Lifecycle</label>
            <select className="form-select" id="resource-lifecycle" onChange={(event) => setDraftLifecycle(event.target.value as ResourceLifecycleStatus | "")} value={draftLifecycle}>
              <option value="">All states</option>
              {RESOURCE_LIFECYCLE_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}
            </select>
          </div>
          <div className="col-12 col-lg-2 d-flex gap-2">
            <button className="btn btn-primary" type="submit">Apply</button>
            <button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button>
          </div>
        </div>
      </form>
      {query.isPending ? <LoadingState label="Resource inventory" /> : null}
      {errorMessage && !connection ? <InitialError label="Resource inventory" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? (
        <>
          {errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
          <ResourceCards
            connection={connection}
            hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))}
          />
          <PaginationControls
            canPrevious={searchParams.getAll("trail").length > 0}
            nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null}
            onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))}
            onPrevious={() => setSearchParams(previousPageParams(searchParams))}
          />
        </>
      ) : null}
    </div>
  );
}

function ResourceDetailPage({ projectRef, resourceId }: {
  readonly projectRef: string;
  readonly resourceId: string;
}) {
  const [searchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/inventory`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useResourceHeading("Resource detail", resourceId);
  const query = useQuery({
    queryKey: ["project-resource", projectRef, resourceId],
    queryFn: ({ signal }) => fetchProjectResource(projectRef, resourceId, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      resourceId
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const resource = query.data?.projectResource ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={`/projects/${projectRef}/resources`} />
      <div>
        <Link className="small" to={backTo}>← Back to Resource inventory</Link>
        <h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Resource detail</h2>
        <p className="text-body-secondary mb-0">Projected identity and lifecycle evidence from ResourceGet.</p>
      </div>
      {query.isPending ? <LoadingState label="Resource detail" /> : null}
      {errorMessage && !resource ? <InitialError label="Resource detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !resource ? <div className="alert alert-info" role="status">This Resource is not available inside the Project.</div> : null}
      {resource ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<ResourceDetail backTo={backTo} resource={resource} /></> : null}
    </div>
  );
}

function ActiveLeasePage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/leases`;
  const sectionPath = `/projects/${projectRef}/resources`;
  const current = {
    agent: searchParams.get("agent") ?? "",
    changeSet: searchParams.get("changeSet") ?? "",
    workItem: searchParams.get("workItem") ?? "",
    attempt: searchParams.get("attempt") ?? ""
  };
  const [draft, setDraft] = useState(current);
  const after = searchParams.get("after");
  const headingRef = useResourceHeading("Active Resource leases", "active-resource-leases");

  useEffect(() => { setDraft(current); }, [current.agent, current.changeSet, current.workItem, current.attempt]);

  const filters: LeaseFilters = {
    ...(current.agent ? { agentId: current.agent } : {}),
    ...(current.changeSet ? { changeSetId: current.changeSet } : {}),
    ...(current.workItem ? { workItemId: current.workItem } : {}),
    ...(current.attempt ? { attemptId: current.attempt } : {})
  };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-active-resource-leases", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchProjectActiveResourceLeases(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      filterKey
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectActiveResourceLeases ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const updateDraft = (key: keyof typeof draft, value: string) => setDraft((valueBefore) => ({ ...valueBefore, [key]: value }));

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={sectionPath} />
      <div>
        <h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Active Resource leases</h2>
        <p className="text-body-secondary mb-0">Inspect factual current holders without inferring ownership from running Attempts.</p>
      </div>
      <form
        aria-label="Active lease filters"
        className="card card-body"
        onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}
      >
        <div className="row g-3">
          {([
            ["agent", "Agent", "lease-agent"],
            ["changeSet", "ChangeSet", "lease-change-set"],
            ["workItem", "WorkItem", "lease-work-item"],
            ["attempt", "Attempt", "lease-attempt"]
          ] as const).map(([key, label, id]) => (
            <div className="col-12 col-md-6" key={key}>
              <label className="form-label" htmlFor={id}>{label}</label>
              <input className="form-control" id={id} onChange={(event) => updateDraft(key, event.target.value)} value={draft[key]} />
            </div>
          ))}
        </div>
        <div className="d-flex gap-2 mt-3">
          <button className="btn btn-primary" type="submit">Apply</button>
          <button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button>
        </div>
      </form>
      {query.isPending ? <LoadingState label="active Resource leases" /> : null}
      {errorMessage && !connection ? <InitialError label="Active Resource leases" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? (
        <>
          {errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
          <LeaseCards
            connection={connection}
            hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))}
          />
          <PaginationControls
            canPrevious={searchParams.getAll("trail").length > 0}
            nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null}
            onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))}
            onPrevious={() => setSearchParams(previousPageParams(searchParams))}
          />
        </>
      ) : null}
    </div>
  );
}

function LeaseDetailPage({ projectRef, leaseId }: {
  readonly projectRef: string;
  readonly leaseId: string;
}) {
  const [searchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/leases`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useResourceHeading("Resource lease detail", leaseId);
  const query = useQuery({
    queryKey: ["project-resource-lease", projectRef, leaseId],
    queryFn: ({ signal }) => fetchProjectResourceLease(projectRef, leaseId, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      leaseId
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const lease = query.data?.projectResourceLease ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={`/projects/${projectRef}/resources`} />
      <div>
        <Link className="small" to={backTo}>← Back to active leases</Link>
        <h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Resource lease detail</h2>
        <p className="text-body-secondary mb-0">Historical lease facts remain available after release, expiry, or Attempt completion.</p>
      </div>
      {query.isPending ? <LoadingState label="Resource lease detail" /> : null}
      {errorMessage && !lease ? <InitialError label="Resource lease detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !lease ? <div className="alert alert-info" role="status">This lease is not available inside the Project.</div> : null}
      {lease ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<LeaseDetail backTo={backTo} lease={lease} projectPath={`/projects/${projectRef}`} /></> : null}
    </div>
  );
}

function validResourceKind(value: string | null): ResourceKind | undefined {
  return RESOURCE_KINDS.some((item) => item.value === value) ? value as ResourceKind : undefined;
}

function validLifecycle(value: string | null): ResourceLifecycleStatus | undefined {
  return RESOURCE_LIFECYCLE_STATUSES.some((item) => item.value === value)
    ? value as ResourceLifecycleStatus
    : undefined;
}
