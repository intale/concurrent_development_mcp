import { useEffect, useRef, useState } from "react";
import type { RefObject } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useLocation, useParams, useSearchParams } from "react-router-dom";
import { fetchSkill, fetchSkillAsset, fetchSkills } from "./project-knowledge-api.js";
import { LatestUpdateSortControl, latestUpdateSortParams, parseLatestUpdateSort } from "../latest-update-sort.js";
import {
  applyFilters,
  listLocation,
  nextPageParams,
  previousPageParams
} from "./project-knowledge-model.js";
import {
  AvailableStale,
  InitialError,
  LoadingState,
  PaginationControls,
  SkillAssetDetail,
  SkillCards,
  SkillDetail,
  useKnowledgeHeading
} from "./project-knowledge-view.js";

const REFRESH_INTERVAL_MS = 15_000;
const LIST_PATH = "/skills";

export function GlobalSkillsPage() {
  const params = useParams<{ readonly "*"?: string; readonly skillId?: string }>();
  const assetPath = params["*"];
  const skillId = params.skillId;
  if (skillId && assetPath) return <GlobalSkillAssetPage assetPath={assetPath} skillId={skillId} />;
  if (skillId) return <GlobalSkillPage skillId={skillId} />;
  return <GlobalSkillListPage />;
}

function GlobalSkillListPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const projectScope = searchParams.get("project") ?? "";
  const name = searchParams.get("name") ?? "";
  const after = searchParams.get("after");
  const sort = parseLatestUpdateSort(searchParams.get("sort"));
  const [draft, setDraft] = useState({ project: projectScope, name });
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => setDraft({ project: projectScope, name }), [projectScope, name]);
  useEffect(() => {
    document.title = "Skills · Coordinator";
    headingRef.current?.focus();
  }, []);

  const query = useQuery({
    queryKey: ["skills", projectScope, name, sort, after],
    queryFn: ({ signal }) => fetchSkills(
      projectScope || undefined,
      name || undefined,
      sort,
      after,
      signal
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.skills ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <>
      <PageHeader headingRef={headingRef} title="Skills" />
      <div className="app-content">
        <div className="container-fluid vstack gap-4">
          <p className="text-body-secondary mb-0">
            Browse every current Skill. Project scope and Skill name filters use exact matching.
          </p>
          <form
            aria-label="Skill filters"
            className="card card-outline card-primary"
            onSubmit={(event) => {
              event.preventDefault();
              setSearchParams(applyFilters(searchParams, draft));
            }}
          >
            <div className="card-header"><h2 className="card-title">Filter Skills</h2></div>
            <div className="card-body row g-3 align-items-end">
              <div className="col-12 col-lg-5">
                <label className="form-label" htmlFor="global-skill-project">Exact Project scope</label>
                <input
                  className="form-control"
                  id="global-skill-project"
                  onChange={(event) => setDraft((value) => ({ ...value, project: event.target.value }))}
                  placeholder="project:example"
                  value={draft.project}
                />
              </div>
              <div className="col-12 col-lg-5">
                <label className="form-label" htmlFor="global-skill-name">Exact Skill name</label>
                <input
                  className="form-control"
                  id="global-skill-name"
                  onChange={(event) => setDraft((value) => ({ ...value, name: event.target.value }))}
                  value={draft.name}
                />
              </div>
              <LatestUpdateSortControl id="global-skill-sort" onChange={(value) => setSearchParams(latestUpdateSortParams(searchParams, value))} value={sort} />
              <div className="col-12 col-lg-auto d-flex gap-2">
                <button className="btn btn-primary" type="submit">Apply</button>
                <button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button>
              </div>
            </div>
          </form>
          {query.isPending ? <LoadingState label="Skills" /> : null}
          {errorMessage && !connection ? <InitialError label="Skills" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
          {connection ? (
            <>
              {errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
              <SkillCards
                connection={connection}
                hrefFor={(skill) => `${LIST_PATH}/${encodeURIComponent(skill.id)}?${new URLSearchParams({ returnTo: listLocation(LIST_PATH, searchParams) })}`}
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
      </div>
    </>
  );
}

function GlobalSkillPage({ skillId }: { readonly skillId: string }) {
  const [searchParams] = useSearchParams();
  const location = useLocation();
  const backTo = safeGlobalReturnTo(searchParams.get("returnTo"), LIST_PATH);
  const headingRef = useKnowledgeHeading("Skill detail", skillId);
  const query = useQuery({
    queryKey: ["skill", skillId],
    queryFn: ({ signal }) => fetchSkill(skillId, signal),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const detail = query.data?.skill ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const currentLocation = `${location.pathname}${location.search}`;

  return (
    <>
      <PageHeader backHref={backTo} headingRef={headingRef} title="Skill detail" />
      <div className="app-content"><div className="container-fluid vstack gap-4">
        {query.isPending ? <LoadingState label="Skill detail" /> : null}
        {errorMessage && !detail ? <InitialError label="Skill detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
        {!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This Skill is not available in the latest projection.</div> : null}
        {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<SkillDetail assetHref={(path) => `${location.pathname}/assets/${encodeAssetPath(path)}?${new URLSearchParams({ returnTo: currentLocation })}`} backTo={backTo} detail={detail} /></> : null}
      </div></div>
    </>
  );
}

function GlobalSkillAssetPage({ skillId, assetPath }: {
  readonly skillId: string;
  readonly assetPath: string;
}) {
  const [searchParams] = useSearchParams();
  const skillPath = `${LIST_PATH}/${encodeURIComponent(skillId)}`;
  const backTo = safeGlobalReturnTo(searchParams.get("returnTo"), skillPath);
  const headingRef = useKnowledgeHeading("Skill asset", `${skillId}:${assetPath}`);
  const query = useQuery({
    queryKey: ["skill-asset", skillId, assetPath],
    queryFn: ({ signal }) => fetchSkillAsset(skillId, assetPath, signal),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const detail = query.data?.skillAsset ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <>
      <PageHeader backHref={backTo} headingRef={headingRef} title="Skill asset" />
      <div className="app-content"><div className="container-fluid vstack gap-4">
        {query.isPending ? <LoadingState label="Skill asset" /> : null}
        {errorMessage && !detail ? <InitialError label="Skill asset" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
        {!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This asset is not available in the latest Skill projection.</div> : null}
        {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<SkillAssetDetail backTo={backTo} detail={detail} /></> : null}
      </div></div>
    </>
  );
}

function PageHeader({ backHref, headingRef, title }: {
  readonly backHref?: string;
  readonly headingRef: RefObject<HTMLHeadingElement>;
  readonly title: string;
}) {
  return (
    <div className="app-content-header">
      <div className="container-fluid">
        <nav aria-label="Breadcrumb"><ol className="breadcrumb mb-2"><li className="breadcrumb-item"><Link to="/projects">Projects</Link></li>{backHref ? <li className="breadcrumb-item"><Link to={backHref}>Skills</Link></li> : null}<li aria-current="page" className="breadcrumb-item active">{title}</li></ol></nav>
        <h1 className="mb-0" ref={headingRef} tabIndex={-1}>{title}</h1>
      </div>
    </div>
  );
}

function safeGlobalReturnTo(value: string | null, fallback: string): string {
  return value === LIST_PATH || value?.startsWith(`${LIST_PATH}?`) || value?.startsWith(`${LIST_PATH}/`)
    ? value
    : fallback;
}

function encodeAssetPath(path: string): string {
  return path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}
