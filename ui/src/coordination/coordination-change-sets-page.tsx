import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import { fetchProjectChangeSet, fetchProjectChangeSets } from "./project-coordination-api.js";
import {
  detailLocation,
  listLocation,
  nextPageParams,
  previousPageParams,
  safeReturnTo
} from "./project-coordination-model.js";
import {
  AvailableStale,
  ChangeSetCards,
  ChangeSetDetail,
  CoordinationNavigation,
  InitialError,
  LoadingState,
  PaginationControls,
  useCoordinationHeading
} from "./project-coordination-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function CoordinationChangeSetsPage() {
  const { changeSetId } = useParams<{ changeSetId?: string }>();
  return changeSetId ? <ChangeSetDetailPage changeSetId={changeSetId} /> : <ChangeSetListPage />;
}

function ChangeSetListPage() {
  const { project, projectRef } = useProjectWorkspace();
  const [searchParams, setSearchParams] = useSearchParams();
  const after = searchParams.get("after") ?? undefined;
  const basePath = `/projects/${projectRef}/coordination`;
  const listPath = `${basePath}/change-sets`;
  const headingRef = useCoordinationHeading(`ChangeSets · ${project.displayLabel}`, after ?? "first");
  const query = useQuery({
    queryKey: ["project-change-sets", projectRef, after],
    queryFn: ({ signal }) => fetchProjectChangeSets(projectRef, after, signal),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectChangeSets;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <CoordinationNavigation basePath={basePath} />
      <div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>ChangeSets</h2><p className="text-body-secondary mb-0">Goals and progress across every Repository member in this Project.</p></div>
      {query.isPending ? <LoadingState label="ChangeSets" /> : null}
      {errorMessage && !connection ? <InitialError label="ChangeSets" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? (
        <>
          {errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
          <ChangeSetCards
            hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))}
            items={connection.nodes}
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

function ChangeSetDetailPage({ changeSetId }: { readonly changeSetId: string }) {
  const { project, projectRef } = useProjectWorkspace();
  const [searchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/coordination`;
  const listPath = `${basePath}/change-sets`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useCoordinationHeading(`ChangeSet · ${project.displayLabel}`, changeSetId);
  const query = useQuery({
    queryKey: ["project-change-set", projectRef, changeSetId],
    queryFn: ({ signal }) => fetchProjectChangeSet(projectRef, changeSetId, signal),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const item = query.data?.projectChangeSet;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <CoordinationNavigation basePath={basePath} />
      <div><Link className="btn btn-outline-secondary mb-3" to={backTo}>← Back to ChangeSets</Link><h2 className="h3 mb-0" ref={headingRef} tabIndex={-1}>ChangeSet detail</h2></div>
      {query.isPending ? <LoadingState label="ChangeSet detail" /> : null}
      {errorMessage && !item ? <InitialError label="ChangeSet detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !item ? <div className="alert alert-info" role="status">This ChangeSet is not available in this Project.</div> : null}
      {item ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<ChangeSetDetail item={item} /></> : null}
    </div>
  );
}
