import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import { fetchProjectDependencies, fetchProjectDependency } from "./project-coordination-api.js";
import { detailLocation, listLocation, nextPageParams, previousPageParams, resetPagination, safeReturnTo } from "./project-coordination-model.js";
import { AvailableStale, CoordinationNavigation, DependencyCards, DependencyDetail, InitialError, LoadingState, PaginationControls, useCoordinationHeading } from "./project-coordination-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function CoordinationDependenciesPage() {
  const { dependencyId } = useParams<{ dependencyId?: string }>();
  return dependencyId ? <DependencyDetailPage dependencyId={dependencyId} /> : <DependencyListPage />;
}

function DependencyListPage() {
  const { project, projectRef } = useProjectWorkspace();
  const [searchParams, setSearchParams] = useSearchParams();
  const requestedState = searchParams.get("state");
  const state = requestedState === "blocking" || requestedState === "satisfied" ? requestedState : "all";
  const blocking = state === "all" ? undefined : state === "blocking";
  const after = searchParams.get("after") ?? undefined;
  const basePath = `/projects/${projectRef}/coordination`;
  const listPath = `${basePath}/dependencies`;
  const headingRef = useCoordinationHeading(`Dependencies · ${project.displayLabel}`, after ?? "first");
  const query = useQuery({ queryKey: ["project-dependencies", projectRef, blocking, after], queryFn: ({ signal }) => fetchProjectDependencies(projectRef, blocking, after, signal), refetchInterval: REFRESH_INTERVAL_MS });
  const connection = query.data?.projectDependencies;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const updateState = (value: string) => { const next = resetPagination(searchParams); if (value === "all") next.delete("state"); else next.set("state", value); setSearchParams(next); };
  return <div className="vstack gap-3"><CoordinationNavigation basePath={basePath} /><div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Dependencies and blockers</h2><p className="text-body-secondary mb-0">Trace the producer and consumer behind every current coordination constraint.</p></div><form aria-label="Dependency filters" className="card card-body" onSubmit={(event) => event.preventDefault()}><div className="col-12 col-md-5"><label className="form-label" htmlFor="dependency-state">State</label><select className="form-select" id="dependency-state" onChange={(event) => updateState(event.target.value)} value={state}><option value="all">All dependencies</option><option value="blocking">Blocking only</option><option value="satisfied">Satisfied only</option></select></div></form>{query.isPending ? <LoadingState label="dependencies" /> : null}{errorMessage && !connection ? <InitialError label="Dependencies" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}{!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}{connection ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<DependencyCards hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} items={connection.nodes} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}</div>;
}

function DependencyDetailPage({ dependencyId }: { readonly dependencyId: string }) {
  const { project, projectRef } = useProjectWorkspace();
  const [searchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/coordination`;
  const listPath = `${basePath}/dependencies`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useCoordinationHeading(`Dependency · ${project.displayLabel}`, dependencyId);
  const query = useQuery({ queryKey: ["project-dependency", projectRef, dependencyId], queryFn: ({ signal }) => fetchProjectDependency(projectRef, dependencyId, signal), refetchInterval: REFRESH_INTERVAL_MS });
  const item = query.data?.projectDependency;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  return <div className="vstack gap-3"><CoordinationNavigation basePath={basePath} /><div><Link className="btn btn-sm btn-outline-secondary mb-3" to={backTo}>← Back to dependencies</Link><h2 className="h3 mb-0" ref={headingRef} tabIndex={-1}>Dependency detail</h2></div>{query.isPending ? <LoadingState label="dependency detail" /> : null}{errorMessage && !item ? <InitialError label="Dependency detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}{!query.isPending && !errorMessage && !item ? <div className="alert alert-info" role="status">This dependency is not available in this Project.</div> : null}{item ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<DependencyDetail item={item} /></> : null}</div>;
}
