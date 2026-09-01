import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { Link, NavLink } from "react-router-dom";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  ArtifactConnection,
  ProjectArtifact,
  ProjectArtifactRelationships,
  ProjectSkill,
  ProjectSkillAsset,
  SkillConnection
} from "./project-knowledge-model.js";
import { humanized } from "./project-knowledge-model.js";

export function useKnowledgeHeading(title: string, focusKey: string): RefObject<HTMLHeadingElement> {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    document.title = `${title} · Coordinator`;
    headingRef.current?.focus();
  }, [focusKey, title]);
  return headingRef;
}

export function KnowledgeNavigation({ basePath }: { readonly basePath: string }) {
  const navClassName = ({ isActive }: { readonly isActive: boolean }) => `nav-link${isActive ? " active" : ""}`;
  return (
    <nav aria-label="Knowledge views" className="mb-3">
      <ul className="nav nav-pills flex-column flex-sm-row gap-2">
        <li className="nav-item"><NavLink className={navClassName} to={`${basePath}/skills`}>Skills</NavLink></li>
        <li className="nav-item"><NavLink className={navClassName} to={`${basePath}/artifacts`}>Development Artifacts</NavLink></li>
      </ul>
    </nav>
  );
}

export function LoadingState({ label }: { readonly label: string }) {
  return (
    <div aria-live="polite" className="card" role="status">
      <div className="card-body d-flex align-items-center gap-3">
        <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
        <span>Loading {label}…</span>
      </div>
    </div>
  );
}

export function InitialError({ label, message, onRetry }: {
  readonly label: string;
  readonly message: string;
  readonly onRetry: () => void;
}) {
  return (
    <div className="alert alert-danger" role="alert">
      <h3 className="h5">{label} could not be loaded</h3>
      <p>{message}</p>
      <RetryRefresh announcementLabel={label} buttonClassName="btn btn-outline-light" onRetry={onRetry}>
        Retry
      </RetryRefresh>
    </div>
  );
}

export function AvailableStale({ message, onRetry }: {
  readonly message: string;
  readonly onRetry: () => void;
}) {
  return (
    <div className="alert alert-warning" role="alert">
      <p>The last available projection remains visible. {message}</p>
      <RetryRefresh
        announcementLabel="Knowledge view"
        buttonClassName="btn btn-outline-dark"
        onRetry={onRetry}
      >
        Retry refresh
      </RetryRefresh>
    </div>
  );
}

export function PaginationControls({ canPrevious, nextCursor, onNext, onPrevious }: {
  readonly canPrevious: boolean;
  readonly nextCursor: string | null;
  readonly onNext: (cursor: string) => void;
  readonly onPrevious: () => void;
}) {
  if (!canPrevious && !nextCursor) return null;
  return (
    <nav aria-label="Collection pages" className="d-flex justify-content-between gap-2">
      <button className="btn btn-outline-secondary" disabled={!canPrevious} onClick={onPrevious} type="button">Previous</button>
      <button className="btn btn-outline-primary" disabled={!nextCursor} onClick={() => nextCursor && onNext(nextCursor)} type="button">Next</button>
    </nav>
  );
}

export function SkillCards({ connection, hrefFor }: {
  readonly connection: SkillConnection;
  readonly hrefFor: (name: string) => string;
}) {
  if (connection.nodes.length === 0) return <div className="alert alert-info" role="status">No Skills match this name.</div>;
  return (
    <div aria-label="Project Skills" className="row g-3">
      {connection.nodes.map((skill) => (
        <div className="col-12 col-xl-6" key={skill.id}>
          <article className="card card-outline card-primary h-100">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 text-break mb-0">{skill.name}</h3>
                <span className="badge text-bg-primary">revision {skill.revision}</span>
              </div>
              <p className="mb-0">{skill.description}</p>
              <div className="small text-body-secondary">{skill.assetCount} assets · published {formatted(skill.publishedAt)}</div>
              <div className="small text-body-secondary text-break">Shared in <code>{skill.scope}</code></div>
              <Link className="btn btn-primary align-self-start mt-auto" to={hrefFor(skill.name)}>View Skill</Link>
            </div>
          </article>
        </div>
      ))}
    </div>
  );
}

export function SkillDetail({ detail, assetHref, backTo }: {
  readonly detail: ProjectSkill;
  readonly assetHref: (path: string) => string;
  readonly backTo: string;
}) {
  const { skill } = detail;
  return (
    <article className="card card-outline card-primary">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break">{skill.name}</h3>
        <span className="badge text-bg-primary">revision {skill.revision}</span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Skill name" value={skill.name} />
        <div><h4 className="h6">Purpose</h4><p className="mb-0">{skill.description}</p></div>
        <Content text={skill.instructions} />
        <section aria-labelledby="skill-assets-heading">
          <h4 className="h6" id="skill-assets-heading">Assets</h4>
          {skill.assets.length === 0 ? <p className="text-body-secondary mb-0">This Skill has no assets.</p> : (
            <div className="list-group">
              {skill.assets.map((asset) => (
                <div className="list-group-item d-flex flex-column flex-sm-row justify-content-between align-items-sm-center gap-2" key={asset.path}>
                  <div className="text-break"><code>{asset.path}</code><div className="small text-body-secondary">{asset.mediaType} · {asset.byteSize} bytes</div></div>
                  <Link className="btn btn-outline-primary align-self-start" to={assetHref(asset.path)}>View asset</Link>
                </div>
              ))}
            </div>
          )}
        </section>
        <DetailEvidence rows={[["Scope", skill.scope], ["Digest", skill.contentDigest], ["Published", formatted(skill.publishedAt)]]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to Skills</Link>
      </div>
    </article>
  );
}

export function SkillAssetDetail({ detail, backTo }: {
  readonly detail: ProjectSkillAsset;
  readonly backTo: string;
}) {
  const { asset } = detail;
  return (
    <article className="card card-outline card-secondary">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break"><code>{asset.path}</code></h3>
        <span className="badge text-bg-secondary">revision {asset.revision}</span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Skill asset path" value={asset.path} />
        <Content base64={asset.base64} text={asset.text} />
        <DetailEvidence rows={[
          ["Media type", asset.mediaType],
          ["Encoding", asset.encoding],
          ["Executable", asset.executable ? "yes" : "no"],
          ["Size", `${asset.byteSize} bytes`],
          ["Digest", asset.contentDigest]
        ]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to Skill</Link>
      </div>
    </article>
  );
}

export function ArtifactCards({ connection, hrefFor }: {
  readonly connection: ArtifactConnection;
  readonly hrefFor: (artifactId: string) => string;
}) {
  if (connection.nodes.length === 0) return <div className="alert alert-info" role="status">No Development Artifacts match these filters.</div>;
  return (
    <div aria-label="Development Artifacts" className="row g-3">
      {connection.nodes.map((artifact) => (
        <div className="col-12 col-xl-6" key={artifact.id}>
          <article className="card card-outline card-info h-100">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 text-break mb-0">{artifact.title}</h3>
                <span className="badge text-bg-info">{humanized(artifact.kind)}</span>
              </div>
              <div className="text-break"><strong>Source:</strong> <code>{artifact.source.locator}</code></div>
              <div className="small text-body-secondary">{artifact.labels.join(", ") || "No labels"} · {artifact.relationshipCount} relationships</div>
              <div className="small text-body-secondary">Observed {formatted(artifact.observedAt)}</div>
              <Link className="btn btn-info align-self-start mt-auto" to={hrefFor(artifact.id)}>View Artifact</Link>
            </div>
          </article>
        </div>
      ))}
    </div>
  );
}

export function ArtifactDetail({ detail, relationshipsHref, backTo }: {
  readonly detail: ProjectArtifact;
  readonly relationshipsHref: string;
  readonly backTo: string;
}) {
  const { artifact, content } = detail;
  return (
    <article className="card card-outline card-info">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break">{artifact.title}</h3>
        <span className="badge text-bg-info">{humanized(artifact.kind)}</span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Artifact ID" value={artifact.id} />
        <CopyIdentifier label="Artifact source" value={artifact.source.locator} />
        <div className="d-flex flex-wrap gap-2">
          <Link className="btn btn-info" to={relationshipsHref}>View {artifact.relationshipCount} relationships</Link>
          <Link className="btn btn-outline-secondary" to={backTo}>Back to Artifacts</Link>
        </div>
        <div className="row g-3">
          <div className="col-12 col-lg-6"><h4 className="h6">Classification</h4><p className="mb-1">{artifact.labels.map((label) => <span className="badge text-bg-secondary me-1" key={label}>{label}</span>)}</p><p className="small text-body-secondary mb-0">Revision {artifact.classificationRevision} · {artifact.classificationReason ?? "No reason recorded"}</p></div>
          <div className="col-12 col-lg-6"><h4 className="h6">Provenance</h4><p className="text-break mb-1">{humanized(artifact.source.kind)} · <code>{artifact.source.locator}</code></p><p className="small text-body-secondary mb-0">Observed {formatted(artifact.source.observedAt)} by {artifact.source.collector}</p></div>
        </div>
        <Content base64={content.base64} text={content.text} />
        <DetailEvidence rows={[
          ["Artifact", artifact.id],
          ["Observation", artifact.observationId],
          ["Scope", artifact.scope],
          ["Digest", content.contentDigest],
          ["Size", `${content.byteSize} bytes`]
        ]} />
      </div>
    </article>
  );
}

export function RelationshipCards({ detail, peerHref }: {
  readonly detail: ProjectArtifactRelationships;
  readonly peerHref: (artifactId: string) => string;
}) {
  if (detail.relationships.nodes.length === 0) return <div className="alert alert-info" role="status">No active relationships match these filters.</div>;
  return (
    <div aria-label="Artifact relationships" className="row g-3">
      {detail.relationships.nodes.map((relationship) => (
        <div className="col-12 col-xl-6" key={`${relationship.direction}:${relationship.id}`}>
          <article className="card h-100">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2"><h3 className="h5 mb-0">{humanized(relationship.displayRelation)}</h3><span className="badge text-bg-secondary">{humanized(relationship.direction)}</span></div>
              <div className="fw-semibold text-break">{relationship.peerArtifact?.title ?? relationship.targetName ?? relationship.peerId}</div>
              <div className="text-break"><code>{relationship.peerArtifact?.source.locator ?? relationship.normalizedLocator ?? relationship.path ?? relationship.peerId}</code></div>
              <div className="small text-body-secondary">Declared {formatted(relationship.declaredAt)} · {relationship.status}</div>
              {relationship.peerArtifact ? <Link className="btn btn-outline-info align-self-start mt-auto" to={peerHref(relationship.peerId)}>View related Artifact</Link> : null}
            </div>
          </article>
        </div>
      ))}
    </div>
  );
}

function Content({ base64, text }: { readonly base64?: string | null; readonly text?: string | null }) {
  if (text !== null && text !== undefined) return <pre className="border rounded bg-body-tertiary p-3 mb-0 text-wrap overflow-auto">{text}</pre>;
  if (base64) return <div className="alert alert-secondary mb-0">Binary content is available through the GraphQL boundary; this browser does not render or transform it.</div>;
  return <div className="text-body-secondary">No content is available in this projection.</div>;
}

function DetailEvidence({ rows }: { readonly rows: ReadonlyArray<readonly [string, string | null | undefined]> }) {
  return (
    <section aria-label="Projected evidence">
      <h4 className="h6">Projected evidence</h4>
      <dl className="row mb-0">
        {rows.map(([label, value]) => (
          <div className="col-12 col-lg-6" key={label}><dt>{label}</dt><dd className="text-break"><code>{value ?? "—"}</code></dd></div>
        ))}
      </dl>
    </section>
  );
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}
