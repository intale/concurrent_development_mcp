import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { MarkdownPreview } from "../markdown/markdown-preview.js";
import { ContextLink as Link } from "../navigation.js";
import { DataTable, TextPreview, Timestamp } from "../data-table.js";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  ArtifactConnection,
  GlobalSkill,
  GlobalSkillAsset,
  GlobalSkillConnection,
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

export function SkillTable({ connection, hrefFor }: {
  readonly connection: SkillConnection | GlobalSkillConnection;
  readonly hrefFor: (skill: SkillConnection["nodes"][number]) => string;
}) {
  return (
    <DataTable caption="Project Skills" rows={connection.nodes} rowKey={(skill) => skill.id} emptyMessage="No Skills match this name." columns={[
      { key: "name", label: "Name", render: (skill) => <><Link to={hrefFor(skill)}>{skill.name}</Link><div className="small text-body-secondary"><TextPreview text={skill.description} /></div></> },
      { key: "scope", label: "Scope", render: (skill) => <code>{skill.scope}</code> },
      { key: "revision", label: "Revision", render: (skill) => skill.revision },
      { key: "assets", label: "Assets", render: (skill) => skill.assetCount },
      { key: "published", label: "Published", render: (skill) => <Timestamp value={skill.publishedAt} /> }
    ]} />
  );
}

export function SkillDetail({ detail, assetHref, backTo }: {
  readonly detail: ProjectSkill | GlobalSkill;
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
        <Content assetLinks={new Map(skill.assets.map((asset) => [asset.path, assetHref(asset.path)]))} mediaType="text/markdown" text={skill.instructions} />
        <section aria-labelledby="skill-assets-heading">
          <h4 className="h6" id="skill-assets-heading">Assets</h4>
          {skill.assets.length === 0 ? <p className="text-body-secondary mb-0">This Skill has no assets.</p> : (
            <DataTable caption="Skill assets" rows={skill.assets} rowKey={(asset) => asset.path} columns={[
              { key: "path", label: "Path", render: (asset) => <Link to={assetHref(asset.path)}><code>{asset.path}</code></Link> },
              { key: "mediaType", label: "Media type", render: (asset) => asset.mediaType },
              { key: "size", label: "Size", render: (asset) => `${asset.byteSize} bytes` },
              { key: "executable", label: "Executable", render: (asset) => asset.executable ? "Yes" : "No" }
            ]} />
          )}
        </section>
        <DetailEvidence rows={[["Scope", skill.scope], ["Digest", skill.contentDigest], ["Published", formatted(skill.publishedAt)]]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to Skills</Link>
      </div>
    </article>
  );
}

export function SkillAssetDetail({ detail, backTo }: {
  readonly detail: ProjectSkillAsset | GlobalSkillAsset;
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
        <Content base64={asset.base64} mediaType={asset.mediaType} text={asset.text} />
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

export function ArtifactTable({ connection, hrefFor }: {
  readonly connection: ArtifactConnection;
  readonly hrefFor: (artifactId: string) => string;
}) {
  return (
    <DataTable caption="Development Artifacts" rows={connection.nodes} rowKey={(artifact) => artifact.id} emptyMessage="No Development Artifacts match these filters." columns={[
      { key: "title", label: "Title", render: (artifact) => <><Link to={hrefFor(artifact.id)}>{artifact.title}</Link><div className="small text-body-secondary"><code>{artifact.source.locator}</code></div></> },
      { key: "kind", label: "Kind", render: (artifact) => humanized(artifact.kind) },
      { key: "labels", label: "Labels", render: (artifact) => <>{artifact.labels.join(", ") || "No labels"}<div className="small text-body-secondary">{artifact.relationshipCount} relationships</div></> },
      { key: "size", label: "Size / media type", render: (artifact) => `${artifact.byteSize} bytes · ${artifact.mediaType}` },
      { key: "captured", label: "Captured", render: (artifact) => <Timestamp value={artifact.capturedAt} /> }
    ]} />
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
        <Content base64={content.base64} mediaType={content.mediaType} text={content.text} />
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

export function RelationshipTable({ detail, peerHref }: {
  readonly detail: ProjectArtifactRelationships;
  readonly peerHref: (artifactId: string) => string;
}) {
  return (
    <DataTable caption="Artifact relationships" rows={detail.relationships.nodes} rowKey={(relationship) => `${relationship.direction}:${relationship.id}`} emptyMessage="No active relationships match these filters." columns={[
      { key: "relation", label: "Relation", render: (relationship) => humanized(relationship.displayRelation) },
      { key: "direction", label: "Direction", render: (relationship) => humanized(relationship.direction) },
      { key: "peer", label: "Related artifact", render: (relationship) => <>{relationship.peerArtifact ? <Link to={peerHref(relationship.peerId)}>{relationship.peerArtifact.title}</Link> : relationship.targetName ?? relationship.peerId}<div className="small"><code>{relationship.peerArtifact?.source.locator ?? relationship.normalizedLocator ?? relationship.path ?? relationship.peerId}</code></div></> },
      { key: "evidence", label: "Evidence", render: (relationship) => <>Declared <Timestamp value={relationship.declaredAt} /> · {relationship.status}</> }
    ]} />
  );
}

function Content({ assetLinks, base64, mediaType, text }: {
  readonly assetLinks?: ReadonlyMap<string, string>;
  readonly base64?: string | null;
  readonly mediaType?: string | null;
  readonly text?: string | null;
}) {
  if (text !== null && text !== undefined && markdownMediaType(mediaType)) {
    return <MarkdownPreview assetLinks={assetLinks} text={text} />;
  }
  if (text !== null && text !== undefined) return <pre className="border rounded bg-body-tertiary p-3 mb-0 text-wrap overflow-auto">{text}</pre>;
  if (base64) return <div className="alert alert-secondary mb-0">Binary content is available through the GraphQL boundary; this browser does not render or transform it.</div>;
  return <div className="text-body-secondary">No content is available in this projection.</div>;
}

function markdownMediaType(mediaType: string | null | undefined): boolean {
  const normalized = mediaType?.split(";", 1)[0]?.trim().toLowerCase();
  return normalized === "text/markdown" || normalized === "text/x-markdown";
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
