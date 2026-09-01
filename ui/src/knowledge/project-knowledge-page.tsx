import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useLocation, useParams, useSearchParams } from "react-router-dom";
import type {
  ArtifactRelationDirection,
  DevelopmentArtifactKind,
  DevelopmentArtifactRelationKind,
  DevelopmentArtifactSourceKind
} from "../gql/graphql.js";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import {
  fetchProjectArtifact,
  fetchProjectArtifactRelationships,
  fetchProjectArtifacts,
  fetchProjectSkill,
  fetchProjectSkillAsset,
  fetchProjectSkills
} from "./project-knowledge-api.js";
import type { ArtifactFilters, RelationshipFilters } from "./project-knowledge-api.js";
import {
  applyFilters,
  ARTIFACT_KINDS,
  ARTIFACT_RELATIONS,
  ARTIFACT_SOURCE_KINDS,
  detailLocation,
  listLocation,
  nextPageParams,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  RELATION_DIRECTIONS,
  safeKnowledgeReturnTo
} from "./project-knowledge-model.js";
import {
  ArtifactCards,
  ArtifactDetail,
  AvailableStale,
  InitialError,
  KnowledgeNavigation,
  LoadingState,
  PaginationControls,
  RelationshipCards,
  SkillAssetDetail,
  SkillCards,
  SkillDetail,
  useKnowledgeHeading
} from "./project-knowledge-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectSkillsPage() {
  const { projectRef } = useProjectWorkspace();
  const params = useParams<{ readonly "*"?: string; readonly skillName?: string }>();
  const assetPath = params["*"];
  const skillName = params.skillName;
  if (skillName && assetPath) return <AssetPage projectRef={projectRef} assetPath={assetPath} skillName={skillName} />;
  if (skillName) return <SkillPage projectRef={projectRef} skillName={skillName} />;
  return <SkillsPage projectRef={projectRef} />;
}

export function ProjectArtifactsPage() {
  const { projectRef } = useProjectWorkspace();
  const { artifactId } = useParams<{ readonly artifactId?: string }>();
  return artifactId ? <ArtifactPage projectRef={projectRef} artifactId={artifactId} /> : <ArtifactsPage projectRef={projectRef} />;
}

export function ProjectArtifactRelationshipsPage() {
  const { projectRef } = useProjectWorkspace();
  const { artifactId = "" } = useParams<{ readonly artifactId: string }>();
  return <RelationshipsPage projectRef={projectRef} artifactId={artifactId} />;
}

function SkillsPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/knowledge/skills`;
  const sectionPath = `/projects/${projectRef}/knowledge`;
  const name = searchParams.get("name") ?? "";
  const after = searchParams.get("after");
  const [draftName, setDraftName] = useState(name);
  const headingRef = useKnowledgeHeading("Project Skills", "project-skills");

  useEffect(() => { setDraftName(name); }, [name]);
  const filterKey = JSON.stringify({ name });
  const query = useQuery({
    queryKey: ["project-skills", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchProjectSkills(projectRef, name || undefined, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(previousData, previousQuery?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectSkills ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <KnowledgeNavigation basePath={sectionPath} />
      <div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Skills</h2><p className="text-body-secondary mb-0">Browse current Skills shared by this exact Project scope.</p></div>
      <form aria-label="Skill filters" className="card card-body" onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, { name: draftName })); }}>
        <div className="row g-3 align-items-end">
          <div className="col-12 col-lg-8"><label className="form-label" htmlFor="skill-name">Exact Skill name</label><input className="form-control" id="skill-name" onChange={(event) => setDraftName(event.target.value)} value={draftName} /></div>
          <div className="col-12 col-lg-4 d-flex gap-2"><button className="btn btn-primary" type="submit">Apply</button><button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button></div>
        </div>
      </form>
      {query.isPending ? <LoadingState label="Skills" /> : null}
      {errorMessage && !connection ? <InitialError label="Skills" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<SkillCards connection={connection} hrefFor={(skill) => detailLocation(listPath, skill, listLocation(listPath, searchParams))} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
      <p className="small text-body-secondary mb-0">Only each Skill&apos;s latest projected revision is shown.</p>
    </div>
  );
}

function SkillPage({ projectRef, skillName }: { readonly projectRef: string; readonly skillName: string }) {
  const [searchParams] = useSearchParams();
  const location = useLocation();
  const listPath = `/projects/${projectRef}/knowledge/skills`;
  const basePath = `/projects/${projectRef}/knowledge`;
  const backTo = safeKnowledgeReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const headingRef = useKnowledgeHeading("Skill detail", skillName);
  const query = useQuery({
    queryKey: ["project-skill", projectRef, skillName],
    queryFn: ({ signal }) => fetchProjectSkill(projectRef, skillName, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(previousData, previousQuery?.queryKey, projectRef, skillName),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const detail = query.data?.projectSkill ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const currentLocation = `${location.pathname}${location.search}`;

  return (
    <div className="vstack gap-3">
      <KnowledgeNavigation basePath={basePath} />
      <div><Link className="small" to={backTo}>← Back to Skills</Link><h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Skill detail</h2><p className="text-body-secondary mb-0">Current instructions and the current asset manifest.</p></div>
      {query.isPending ? <LoadingState label="Skill detail" /> : null}
      {errorMessage && !detail ? <InitialError label="Skill detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This Skill is not available inside the Project.</div> : null}
      {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<SkillDetail assetHref={(path) => `${location.pathname}/assets/${encodeAssetPath(path)}?${new URLSearchParams({ returnTo: currentLocation }).toString()}`} backTo={backTo} detail={detail} /></> : null}
    </div>
  );
}

function AssetPage({ projectRef, skillName, assetPath }: {
  readonly projectRef: string;
  readonly skillName: string;
  readonly assetPath: string;
}) {
  const [searchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/knowledge/skills`;
  const basePath = `/projects/${projectRef}/knowledge`;
  const skillPath = `${listPath}/${encodeURIComponent(skillName)}`;
  const backTo = safeKnowledgeReturnTo(searchParams.get("returnTo"), skillPath, basePath);
  const identity = `${skillName}:${assetPath}`;
  const headingRef = useKnowledgeHeading("Skill asset", identity);
  const query = useQuery({
    queryKey: ["project-skill-asset", projectRef, identity],
    queryFn: ({ signal }) => fetchProjectSkillAsset(projectRef, skillName, assetPath, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(previousData, previousQuery?.queryKey, projectRef, identity),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const detail = query.data?.projectSkillAsset ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <KnowledgeNavigation basePath={basePath} />
      <div><Link className="small" to={backTo}>← Back to Skill</Link><h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Skill asset</h2><p className="text-body-secondary mb-0">Exact current content and projection evidence for one asset.</p></div>
      {query.isPending ? <LoadingState label="Skill asset" /> : null}
      {errorMessage && !detail ? <InitialError label="Skill asset" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This asset is not available in the current Skill revision.</div> : null}
      {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<SkillAssetDetail backTo={backTo} detail={detail} /></> : null}
    </div>
  );
}

function ArtifactsPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/knowledge/artifacts`;
  const sectionPath = `/projects/${projectRef}/knowledge`;
  const kind = validArtifactKind(searchParams.get("kind"));
  const sourceKind = validSourceKind(searchParams.get("source"));
  const labelValue = searchParams.get("labels") ?? "";
  const labels = labelValue.split(",").map((label) => label.trim()).filter(Boolean);
  const after = searchParams.get("after");
  const current = { kind: kind ?? "", source: sourceKind ?? "", labels: labelValue };
  const [draft, setDraft] = useState(current);
  const headingRef = useKnowledgeHeading("Development Artifacts", "development-artifacts");
  useEffect(() => { setDraft(current); }, [current.kind, current.source, current.labels]);

  const filters: ArtifactFilters = { labels, ...(kind ? { kind } : {}), ...(sourceKind ? { sourceKind } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-artifacts", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchProjectArtifacts(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(previousData, previousQuery?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectArtifacts ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <KnowledgeNavigation basePath={sectionPath} />
      <div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Development Artifacts</h2><p className="text-body-secondary mb-0">Find documents, evidence, plans, and references captured for this exact Project scope.</p></div>
      <form aria-label="Artifact filters" className="card card-body" onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}>
        <div className="row g-3 align-items-end">
          <div className="col-12 col-md-6 col-xl-3"><label className="form-label" htmlFor="artifact-kind">Kind</label><select className="form-select" id="artifact-kind" onChange={(event) => setDraft((value) => ({ ...value, kind: event.target.value as DevelopmentArtifactKind | "" }))} value={draft.kind}><option value="">All kinds</option>{ARTIFACT_KINDS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
          <div className="col-12 col-md-6 col-xl-3"><label className="form-label" htmlFor="artifact-source">Source</label><select className="form-select" id="artifact-source" onChange={(event) => setDraft((value) => ({ ...value, source: event.target.value as DevelopmentArtifactSourceKind | "" }))} value={draft.source}><option value="">All sources</option>{ARTIFACT_SOURCE_KINDS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
          <div className="col-12 col-xl-4"><label className="form-label" htmlFor="artifact-labels">Labels</label><input className="form-control" id="artifact-labels" onChange={(event) => setDraft((value) => ({ ...value, labels: event.target.value }))} placeholder="Comma separated" value={draft.labels} /></div>
          <div className="col-12 col-xl-2 d-flex gap-2"><button className="btn btn-info" type="submit">Apply</button><button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button></div>
        </div>
      </form>
      {query.isPending ? <LoadingState label="Development Artifacts" /> : null}
      {errorMessage && !connection ? <InitialError label="Development Artifacts" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<ArtifactCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
    </div>
  );
}

function ArtifactPage({ projectRef, artifactId }: { readonly projectRef: string; readonly artifactId: string }) {
  const [searchParams] = useSearchParams();
  const location = useLocation();
  const listPath = `/projects/${projectRef}/knowledge/artifacts`;
  const basePath = `/projects/${projectRef}/knowledge`;
  const backTo = safeKnowledgeReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const headingRef = useKnowledgeHeading("Artifact detail", artifactId);
  const query = useQuery({
    queryKey: ["project-artifact", projectRef, artifactId],
    queryFn: ({ signal }) => fetchProjectArtifact(projectRef, artifactId, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(previousData, previousQuery?.queryKey, projectRef, artifactId),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const detail = query.data?.projectArtifact ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const currentLocation = `${location.pathname}${location.search}`;
  const relationshipsHref = `${location.pathname}/relationships?${new URLSearchParams({ returnTo: currentLocation }).toString()}`;

  return (
    <div className="vstack gap-3">
      <KnowledgeNavigation basePath={basePath} />
      <div><Link className="small" to={backTo}>← Back to Development Artifacts</Link><h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Artifact detail</h2><p className="text-body-secondary mb-0">Classification, provenance, and exact current content.</p></div>
      {query.isPending ? <LoadingState label="Artifact detail" /> : null}
      {errorMessage && !detail ? <InitialError label="Artifact detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This Artifact is not available inside the Project.</div> : null}
      {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<ArtifactDetail backTo={backTo} detail={detail} relationshipsHref={relationshipsHref} /></> : null}
    </div>
  );
}

function RelationshipsPage({ projectRef, artifactId }: { readonly projectRef: string; readonly artifactId: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const location = useLocation();
  const listPath = `/projects/${projectRef}/knowledge/artifacts`;
  const basePath = `/projects/${projectRef}/knowledge`;
  const artifactPath = `${listPath}/${encodeURIComponent(artifactId)}`;
  const backTo = safeKnowledgeReturnTo(searchParams.get("returnTo"), artifactPath, basePath);
  const direction = validDirection(searchParams.get("direction"));
  const relation = validRelation(searchParams.get("relation"));
  const after = searchParams.get("after");
  const filters: RelationshipFilters = { direction, ...(relation ? { relation } : {}) };
  const filterKey = JSON.stringify(filters);
  const headingRef = useKnowledgeHeading("Artifact relationships", artifactId);
  const query = useQuery({
    queryKey: ["project-artifact-relationships", projectRef, `${artifactId}:${filterKey}`, after],
    queryFn: ({ signal }) => fetchProjectArtifactRelationships(projectRef, artifactId, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(previousData, previousQuery?.queryKey, projectRef, `${artifactId}:${filterKey}`),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const detail = query.data?.projectArtifactRelationships ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const currentLocation = `${location.pathname}${location.search}`;

  return (
    <div className="vstack gap-3">
      <KnowledgeNavigation basePath={basePath} />
      <div><Link className="small" to={backTo}>← Back to Artifact</Link><h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Artifact relationships</h2><p className="text-body-secondary mb-0">Active incoming and outgoing semantic links with explicit direction and provenance.</p></div>
      <form aria-label="Relationship filters" className="card card-body">
        <div className="row g-3">
          <div className="col-12 col-md-6"><label className="form-label" htmlFor="relationship-direction">Direction</label><select className="form-select" id="relationship-direction" onChange={(event) => setSearchParams(applyFilters(searchParams, { direction: event.target.value, relation: relation ?? "" }))} value={direction}>{RELATION_DIRECTIONS.map((value) => <option key={value} value={value}>{value.toLowerCase()}</option>)}</select></div>
          <div className="col-12 col-md-6"><label className="form-label" htmlFor="relationship-kind">Relationship</label><select className="form-select" id="relationship-kind" onChange={(event) => setSearchParams(applyFilters(searchParams, { direction, relation: event.target.value }))} value={relation ?? ""}><option value="">All relationships</option>{ARTIFACT_RELATIONS.map((value) => <option key={value} value={value}>{value.toLowerCase().replaceAll("_", " ")}</option>)}</select></div>
        </div>
      </form>
      {query.isPending ? <LoadingState label="Artifact relationships" /> : null}
      {errorMessage && !detail ? <InitialError label="Artifact relationships" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This Artifact is not available inside the Project.</div> : null}
      {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<div className="card card-body"><h3 className="h5 mb-1">{detail.artifact.title}</h3><div className="small text-body-secondary text-break"><code>{detail.artifact.source.locator}</code></div></div><RelationshipCards detail={detail} peerHref={(id) => detailLocation(listPath, id, currentLocation)} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={detail.relationships.pageInfo.hasNextPage ? detail.relationships.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
      <p className="small text-body-secondary mb-0">Superseded relationship edges are intentionally absent from this latest projection.</p>
    </div>
  );
}

function validArtifactKind(value: string | null): DevelopmentArtifactKind | undefined {
  return ARTIFACT_KINDS.find((option) => option.value === value)?.value;
}

function validSourceKind(value: string | null): DevelopmentArtifactSourceKind | undefined {
  return ARTIFACT_SOURCE_KINDS.find((option) => option.value === value)?.value;
}

function validDirection(value: string | null): ArtifactRelationDirection {
  return RELATION_DIRECTIONS.includes(value as ArtifactRelationDirection) ? value as ArtifactRelationDirection : "BOTH";
}

function validRelation(value: string | null): DevelopmentArtifactRelationKind | undefined {
  return ARTIFACT_RELATIONS.includes(value as DevelopmentArtifactRelationKind) ? value as DevelopmentArtifactRelationKind : undefined;
}

function encodeAssetPath(path: string): string {
  return path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}
