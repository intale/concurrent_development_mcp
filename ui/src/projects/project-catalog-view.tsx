import { Link } from "react-router-dom";
import { RetryRefresh } from "../retry-refresh.js";
import type { ProjectRow } from "./project-catalog-model.js";

export interface ProjectCatalogViewProps {
  readonly canGoBack: boolean;
  readonly errorMessage: string | null;
  readonly hasNextPage: boolean;
  readonly loading: boolean;
  readonly onNext: () => void;
  readonly onPrevious: () => void;
  readonly onRetry: () => void;
  readonly pageNumber: number;
  readonly rows: readonly ProjectRow[];
  readonly searchApplied: boolean;
  readonly showingPreviousData: boolean;
}

export function ProjectCatalogView(props: ProjectCatalogViewProps) {
  if (props.loading && props.rows.length === 0) {
    return (
      <div aria-live="polite" className="card" role="status">
        <div className="card-body d-flex align-items-center gap-3">
          <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
          <span>Loading available projects…</span>
        </div>
      </div>
    );
  }

  if (props.errorMessage && props.rows.length === 0) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">
          <i aria-hidden="true" className="bi bi-exclamation-triangle me-2" />
          Projects could not be loaded
        </h2>
        <p>{props.errorMessage}</p>
        <RetryRefresh
          announcementLabel="Project catalog"
          buttonClassName="btn btn-outline-light"
          onRetry={props.onRetry}
        >
          Retry
        </RetryRefresh>
      </div>
    );
  }

  if (props.rows.length === 0) {
    return (
      <div className="card">
        <div className="card-header"><h2 className="card-title">No available projects</h2></div>
        <div className="card-body">
          {props.searchApplied
            ? "No Project scope or Repository member matches this search. Clear or change the refinement."
            : "No Project scopes are currently available in the Repository projection."}
        </div>
      </div>
    );
  }

  return (
    <section aria-labelledby="available-projects-heading" className="vstack gap-3">
      {props.errorMessage ? (
        <div className="alert alert-warning" role="alert">
          <h2 className="h5">
            <i aria-hidden="true" className="bi bi-arrow-clockwise me-2" />
            Refresh failed
          </h2>
          <p>The last available Project page remains visible. {props.errorMessage}</p>
          <RetryRefresh
            announcementLabel="Project catalog"
            buttonClassName="btn btn-outline-dark"
            onRetry={props.onRetry}
          >
            Retry refresh
          </RetryRefresh>
        </div>
      ) : null}
      <div className="d-flex flex-wrap align-items-center justify-content-between gap-2">
        <div>
          <h2 className="h4 mb-1" id="available-projects-heading">Available projects</h2>
          <p className="small text-body-secondary mb-0">
            Page {props.pageNumber} · {props.rows.length} {props.rows.length === 1 ? "Project" : "Projects"}
          </p>
        </div>
        <span
          aria-atomic="true"
          aria-live="polite"
          className="small text-body-secondary"
        >
          {props.showingPreviousData ? <><i aria-hidden="true" className="bi bi-arrow-repeat me-1" />Loading the requested page…</> : "\u00a0"}
        </span>
      </div>
      <div className="row row-cols-1 row-cols-xl-2 g-3">
        {props.rows.map((project) => (
          <div className="col" key={project.projectRef}>
            <article className="card card-outline card-primary h-100">
              <div className="card-header d-flex align-items-start justify-content-between gap-3">
                <div>
                  <h3 className="card-title fw-semibold mb-1">{project.displayLabel}</h3>
                  <div className="small text-body-secondary text-break"><code>{project.scope}</code></div>
                </div>
                <span className="badge text-bg-secondary text-nowrap">
                  {project.repositoryCount} {project.repositoryCount === 1 ? "Repository" : "Repositories"}
                </span>
              </div>
              <div className="card-body">
                <h4 className="h6">Repository members</h4>
                <ul className="list-group list-group-flush">
                  {project.repositories.map((repository) => (
                    <li className="list-group-item px-0" key={repository.id}>
                      <div className="fw-medium">{repository.displayName}</div>
                      <div className="small text-body-secondary text-break">
                        {repository.paths[0] ?? "No projected path"}
                      </div>
                    </li>
                  ))}
                </ul>
                {project.hasMoreRepositories ? (
                  <p className="small text-body-secondary mt-2 mb-0">
                    More Repository members are available in the Project overview.
                  </p>
                ) : null}
              </div>
              <div className="card-footer d-grid">
                <Link className="btn btn-primary" to={`/projects/${project.projectRef}`}>
                  Open project <i aria-hidden="true" className="bi bi-arrow-right ms-1" />
                </Link>
              </div>
            </article>
          </div>
        ))}
      </div>
      <nav aria-label="Project catalog pagination" className="d-flex align-items-center justify-content-between gap-3">
        <button
          className="btn btn-outline-secondary"
          disabled={!props.canGoBack}
          onClick={props.onPrevious}
          type="button"
        >
          Previous page
        </button>
        <button
          className="btn btn-outline-primary"
          disabled={!props.hasNextPage}
          onClick={props.onNext}
          type="button"
        >
          Next page
        </button>
      </nav>
    </section>
  );
}
