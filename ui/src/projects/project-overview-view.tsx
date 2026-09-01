import { Link } from "react-router-dom";

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
  readonly refreshing: boolean;
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
        <button className="btn btn-outline-light" onClick={props.onRetry} type="button">Retry</button>
      </div>
    );
  }

  return (
    <>
      {props.errorMessage ? (
        <div className="alert alert-warning" role="alert">
          The last available Repository page remains visible. {props.errorMessage}
        </div>
      ) : null}
      <div className="row g-3">
        <div className="col-12 col-lg-6">
          <div className="small-box text-bg-primary h-100">
            <div className="inner">
              <h3>{props.repositoryCount}</h3>
              <p>Registered {props.repositoryCount === 1 ? "Repository member" : "Repository members"}</p>
            </div>
            <i aria-hidden="true" className="small-box-icon bi bi-git" />
          </div>
        </div>
        <div className="col-12 col-lg-6">
          <div className="card h-100">
            <div className="card-header"><h3 className="card-title">Continue work</h3></div>
            <div className="card-body d-grid d-sm-flex gap-2">
              <Link className="btn btn-primary" to={`/projects/${props.projectRef}/coordination`}>
                Open coordination
              </Link>
              <Link className="btn btn-outline-primary" to={`/projects/${props.projectRef}/resources`}>
                Inspect resources
              </Link>
            </div>
          </div>
        </div>
      </div>
      <section aria-labelledby="repository-members-heading" className="vstack gap-3">
        <div className="d-flex flex-wrap justify-content-between align-items-center gap-2">
          <div>
            <h3 className="h4 mb-1" id="repository-members-heading">Repository members</h3>
            <p className="small text-body-secondary mb-0">Page {props.pageNumber}</p>
          </div>
          {props.refreshing ? <span className="small text-body-secondary">Refreshing…</span> : null}
        </div>
        {props.repositories.length === 0 ? (
          <div className="card"><div className="card-body">No Repository members are available on this page.</div></div>
        ) : (
          <div className="row row-cols-1 row-cols-lg-2 g-3">
            {props.repositories.map((repository) => (
              <div className="col" key={repository.id}>
                <article className="card h-100">
                  <div className="card-header"><h4 className="card-title fw-semibold">{repository.displayName}</h4></div>
                  <div className="card-body vstack gap-3">
                    <div>
                      <div className="small fw-semibold text-uppercase text-body-secondary">Paths</div>
                      {repository.paths.length > 0
                        ? repository.paths.map((path) => <div className="text-break" key={path}>{path}</div>)
                        : <span className="text-body-secondary">No projected paths</span>}
                    </div>
                    <div>
                      <div className="small fw-semibold text-uppercase text-body-secondary">Remotes</div>
                      {repository.remotes.length > 0
                        ? repository.remotes.map((remote) => <div className="text-break" key={remote}>{remote}</div>)
                        : <span className="text-body-secondary">No projected remotes</span>}
                    </div>
                    <div className="small text-body-secondary">
                      Registered <time dateTime={repository.registeredAt}>{repository.registeredAt}</time>
                    </div>
                  </div>
                  <div className="card-footer small text-body-secondary text-break">
                    Repository ID <code>{repository.id}</code>
                  </div>
                </article>
              </div>
            ))}
          </div>
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
