import { useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { fetchProjects } from "./project-catalog-api.js";
import {
  nextProjectPageParameters,
  parseProjectSort,
  preservePageForCatalogFilters,
  previousProjectPageParameters,
  resetProjectPagination
} from "./project-catalog-model.js";
import type { ProjectRow } from "./project-catalog-model.js";
import { ProjectCatalogView } from "./project-catalog-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectCatalogPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const search = searchParams.get("q") ?? "";
  const sort = parseProjectSort(searchParams.get("sort"));
  const after = searchParams.get("after");
  const pageNumber = searchParams.getAll("trail").length + 1;
  const [searchDraft, setSearchDraft] = useState(search);
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    setSearchDraft(search);
  }, [search]);

  useEffect(() => {
    document.title = "Projects · Coordinator";
    headingRef.current?.focus();
  }, []);

  const filters = useMemo(() => ({
    ...(search ? { search } : {}),
    sort
  }), [search, sort]);
  const projects = useQuery({
    queryKey: ["projects", search, sort, after],
    queryFn: ({ signal }) => fetchProjects(filters, after, signal),
    placeholderData: (previousData, previousQuery) => (
      preservePageForCatalogFilters(previousData, previousQuery?.queryKey, search, sort)
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const rows = useMemo<readonly ProjectRow[]>(() => (
    projects.data?.projects.nodes.map((project) => ({
      projectRef: project.projectRef,
      displayLabel: project.displayLabel,
      repositoryCount: project.repositoryCount,
      scope: project.scope,
      hasMoreRepositories: project.repositories.pageInfo.hasNextPage,
      repositories: project.repositories.nodes.map((repository) => ({
        id: repository.id,
        displayName: repository.displayName ?? repository.paths[0] ?? repository.id,
        paths: repository.paths
      }))
    })) ?? []
  ), [projects.data]);

  const submitSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const next = resetProjectPagination(searchParams);
    const query = searchDraft.trim();
    if (query) next.set("q", query);
    else next.delete("q");
    setSearchParams(next);
  };

  const changeSort = (value: string) => {
    const next = resetProjectPagination(searchParams);
    const selected = parseProjectSort(value);
    if (selected === "NEWEST_FIRST") next.delete("sort");
    else next.set("sort", selected);
    setSearchParams(next);
  };

  const goNext = () => {
    const cursor = projects.data?.projects.pageInfo.endCursor;
    if (cursor) setSearchParams(nextProjectPageParameters(searchParams, cursor));
  };

  const errorMessage = projects.error instanceof Error ? projects.error.message : null;

  return (
    <>
      <div className="app-content-header">
        <div className="container-fluid">
          <div className="row align-items-center">
            <div className="col-sm-6">
              <h1 className="mb-0" ref={headingRef} tabIndex={-1}>Projects</h1>
            </div>
            <div className="col-sm-6">
              <nav aria-label="Breadcrumb">
                <ol className="breadcrumb float-sm-end mb-0">
                  <li aria-current="page" className="breadcrumb-item active">Projects</li>
                </ol>
              </nav>
            </div>
          </div>
        </div>
      </div>
      <div className="app-content">
        <div className="container-fluid vstack gap-4">
          <p className="text-body-secondary mb-0">
            Discover exact coordination scopes from the latest available Repository projections.
            Available data remains usable while projections catch up.
          </p>
          <form className="card card-outline card-primary" onSubmit={submitSearch}>
            <div className="card-header"><h2 className="card-title">Refine projects</h2></div>
            <div className="card-body row g-3 align-items-end">
              <div className="col-12 col-lg">
                <label className="form-label" htmlFor="project-search">Search</label>
                <input
                  className="form-control"
                  id="project-search"
                  maxLength={200}
                  onChange={(event) => setSearchDraft(event.target.value)}
                  placeholder="Scope, Repository name, or path"
                  type="search"
                  value={searchDraft}
                />
              </div>
              <div className="col-12 col-sm-7 col-lg-3">
                <label className="form-label" htmlFor="project-sort">Order</label>
                <select
                  className="form-select"
                  id="project-sort"
                  onChange={(event) => changeSort(event.target.value)}
                  value={sort}
                >
                  <option value="NEWEST_FIRST">Recently updated</option>
                  <option value="OLDEST_FIRST">Least recently updated</option>
                </select>
              </div>
              <div className="col-12 col-sm-5 col-lg-auto d-grid">
                <button className="btn btn-primary" type="submit">Apply search</button>
              </div>
            </div>
          </form>
          <ProjectCatalogView
            canGoBack={searchParams.has("trail")}
            errorMessage={errorMessage}
            hasNextPage={projects.data?.projects.pageInfo.hasNextPage ?? false}
            loading={projects.isPending}
            onNext={goNext}
            onPrevious={() => setSearchParams(previousProjectPageParameters(searchParams))}
            onRetry={() => { void projects.refetch(); }}
            pageNumber={pageNumber}
            rows={rows}
            searchApplied={search.length > 0}
            showingPreviousData={projects.isPlaceholderData}
          />
        </div>
      </div>
    </>
  );
}
