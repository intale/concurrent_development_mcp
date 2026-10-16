import { ContextLink as Link, projectPath } from "../navigation.js";
import { DataTable, Timestamp } from "../data-table.js";
import { RetryRefresh } from "../retry-refresh.js";

export interface ProjectOverviewRepository {
  readonly displayName: string;
  readonly id: string;
  readonly paths: readonly string[];
  readonly registeredAt: string;
  readonly remotes: readonly string[];
}

export interface ProjectOverviewViewProps {
  readonly canGoBack: boolean;
  readonly errorMessage: string | null;
  readonly hasNextPage: boolean;
  readonly loading: boolean;
  readonly onNext: () => void;
  readonly onPrevious: () => void;
  readonly onRetry: () => void;
  readonly pageNumber: number;
  readonly projectRef: string;
  readonly loadingRequestedPage: boolean;
  readonly repositories: readonly ProjectOverviewRepository[];
  readonly repositoryCount: number;
}

export function ProjectOverviewView(props: ProjectOverviewViewProps) {
  if (props.loading && props.repositories.length === 0) {
    return (
      <div aria-live="polite" className="card" role="status">
        <div className="card-body d-flex align-items-center gap-3">
          <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
          <span>Loading Project overview…</span>
        </div>
      </div>
    );
  }

  if (props.errorMessage && props.repositories.length === 0) {
    return (
      <div className="alert alert-danger" role="alert">
        <h3 className="h5">Project overview could not be loaded</h3>
        <p>{props.errorMessage}</p>
        <RetryRefresh
          announcementLabel="Project overview"
          buttonClassName="btn btn-outline-light"
          onRetry={props.onRetry}
        >
          Retry
        </RetryRefresh>
      </div>
    );
  }

  return (
    <>
      {props.errorMessage ? (
        <div className="alert alert-warning" role="alert">
          <p>The last available Repository page remains visible. {props.errorMessage}</p>
          <RetryRefresh
            announcementLabel="Project overview"
            buttonClassName="btn btn-outline-dark"
            onRetry={props.onRetry}
          >
            Retry refresh
          </RetryRefresh>
        </div>
      ) : null}
      <div className="d-flex flex-wrap align-items-center justify-content-between gap-3 my-3">
        <div><h2 className="h3 mb-1">Project overview</h2><p className="mb-0 text-body-secondary">{props.repositoryCount} registered {props.repositoryCount === 1 ? "repository" : "repositories"}. Choose a section in the sidebar to inspect work or knowledge.</p></div>
        <div className="d-flex flex-wrap gap-2"><Link className="btn btn-primary" to={`${projectPath(props.projectRef)}/work-items`}>View work items</Link><Link className="btn btn-outline-secondary" to={`${projectPath(props.projectRef)}/resources`}>View resources</Link></div>
      </div>
      <section aria-labelledby="repository-members-heading" className="vstack gap-3">
        <div className="d-flex flex-wrap justify-content-between align-items-center gap-2">
          <div>
            <h3 className="h4 mb-1" id="repository-members-heading">Repository members</h3>
            <p className="small text-body-secondary mb-0">Page {props.pageNumber}</p>
          </div>
          <span
            aria-atomic="true"
            aria-live="polite"
            className="small text-body-secondary"
          >
            {props.loadingRequestedPage ? "Loading the requested page…" : "\u00a0"}
          </span>
        </div>
        {props.repositories.length === 0 ? (
          <div className="card"><div className="card-body">No Repository members are available on this page.</div></div>
        ) : (
          <DataTable caption="Repository members" rows={props.repositories} rowKey={(repository) => repository.id} columns={[
            { key: "name", label: "Repository", render: (repository) => <><span className="fw-semibold">{repository.displayName}</span><div className="small text-body-secondary">{repository.id}</div></> },
            { key: "paths", label: "Paths", render: (repository) => repository.paths.join(", ") || "No projected paths" },
            { key: "remotes", label: "Remotes", className: "d-none d-lg-table-cell", render: (repository) => repository.remotes.join(", ") || "No projected remotes" },
            { key: "registered", label: "Registered", render: (repository) => <Timestamp value={repository.registeredAt} /> }
          ]} />
        )}
        <nav aria-label="Repository member pagination" className="d-flex justify-content-between gap-3">
          <button className="btn btn-outline-secondary" disabled={!props.canGoBack} onClick={props.onPrevious} type="button">
            Previous page
          </button>
          <button className="btn btn-outline-primary" disabled={!props.hasNextPage} onClick={props.onNext} type="button">
            Next page
          </button>
        </nav>
      </section>
    </>
  );
}
