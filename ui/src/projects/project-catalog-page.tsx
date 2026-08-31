import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { fetchProjects } from "./project-catalog-api.js";
import { preservePageForExactScope } from "./project-catalog-model.js";
import type { ProjectRow } from "./project-catalog-model.js";
import { ProjectCatalogView } from "./project-catalog-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectCatalogPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const exactScope = searchParams.get("scope") ?? "";
  const [scopeDraft, setScopeDraft] = useState(exactScope);
  const [pageIndex, setPageIndex] = useState(0);
  const [cursors, setCursors] = useState<readonly (string | null)[]>([null]);

  useEffect(() => {
    setScopeDraft(exactScope);
    setPageIndex(0);
    setCursors([null]);
  }, [exactScope]);

  const after = cursors[pageIndex] ?? null;
  const projects = useQuery({
    queryKey: ["projects", exactScope, after],
    queryFn: ({ signal }) => fetchProjects(exactScope, after, signal),
    enabled: exactScope.length > 0,
    placeholderData: (previousData, previousQuery) => (
      preservePageForExactScope(previousData, previousQuery?.queryKey, exactScope)
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const rows = useMemo<readonly ProjectRow[]>(() => (
    projects.data?.projects.nodes.map((project) => ({
      id: project.id,
      name: project.name ?? "Unnamed project",
      paths: project.paths.join(", "),
      registeredAt: project.registeredAt,
      remotes: project.remotes.join(", "),
      scope: project.scope
    })) ?? []
  ), [projects.data]);

  const submitScope = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const scope = scopeDraft.trim();
    setSearchParams(scope ? { scope } : {});
  };

  const goNext = () => {
    const cursor = projects.data?.projects.pageInfo.endCursor;
    if (!cursor) return;

    setCursors((current) => {
      const next = current.slice(0, pageIndex + 1);
      next[pageIndex + 1] = cursor;
      return next;
    });
    setPageIndex((current) => current + 1);
  };

  const errorMessage = projects.error instanceof Error ? projects.error.message : null;

  return (
    <>
      <div className="app-content-header">
        <div className="container-fluid">
          <div className="row align-items-center">
            <div className="col-sm-6"><h1 className="mb-0">Project catalog</h1></div>
            <div className="col-sm-6">
              <ol className="breadcrumb float-sm-end mb-0">
                <li aria-current="page" className="breadcrumb-item active">Projects</li>
              </ol>
            </div>
          </div>
        </div>
      </div>
      <div className="app-content">
        <div className="container-fluid vstack gap-4">
          <p className="text-body-secondary mb-0">
            Read the latest available repository registrations without turning projection freshness into a gate.
          </p>
          <form className="row g-3 align-items-end" onSubmit={submitScope}>
            <div className="col-12 col-md">
              <label className="form-label" htmlFor="project-scope">Exact project scope</label>
              <input
                className="form-control"
                id="project-scope"
                maxLength={500}
                onChange={(event) => setScopeDraft(event.target.value)}
                placeholder="project:example"
                type="text"
                value={scopeDraft}
              />
            </div>
            <div className="col-12 col-md-auto d-grid">
              <button className="btn btn-primary" type="submit">Load projects</button>
            </div>
          </form>
          <ProjectCatalogView
            canGoBack={pageIndex > 0}
            errorMessage={errorMessage}
            hasNextPage={projects.data?.projects.pageInfo.hasNextPage ?? false}
            loading={projects.isPending}
            onNext={goNext}
            onPrevious={() => setPageIndex((current) => Math.max(0, current - 1))}
            onRetry={() => { void projects.refetch(); }}
            refreshing={projects.isFetching && projects.data !== undefined}
            rows={rows}
            scopeRequired={exactScope.length === 0}
            showingPreviousData={projects.isPlaceholderData}
          />
        </div>
      </div>
    </>
  );
}
