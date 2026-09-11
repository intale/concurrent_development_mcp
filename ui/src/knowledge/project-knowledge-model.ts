import type {
  ArtifactRelationDirection,
  ArtifactSummaryFieldsFragment,
  DevelopmentArtifactKind,
  DevelopmentArtifactRelationKind,
  DevelopmentArtifactSourceKind,
  ProjectArtifactQuery,
  ProjectArtifactRelationshipsQuery,
  ProjectArtifactsQuery,
  ProjectSkillAssetQuery,
  ProjectSkillQuery,
  ProjectSkillsQuery,
  SkillAssetQuery,
  SkillQuery,
  SkillsQuery,
  SkillSummaryFieldsFragment
} from "../gql/graphql.js";

export const ARTIFACT_KINDS: ReadonlyArray<{
  readonly label: string;
  readonly value: DevelopmentArtifactKind;
}> = [
  { label: "Build manifests", value: "BUILD_MANIFEST" },
  { label: "Build plans", value: "BUILD_PLAN" },
  { label: "Contracts", value: "CONTRACT" },
  { label: "Decision logs", value: "DECISION_LOG" },
  { label: "Decision records", value: "DECISION_RECORD" },
  { label: "Documentation", value: "DOCUMENTATION" },
  { label: "Event models", value: "EVENT_MODEL" },
  { label: "External references", value: "EXTERNAL_REFERENCE" },
  { label: "Governance", value: "GOVERNANCE" },
  { label: "Implementation records", value: "IMPLEMENTATION_RECORD" },
  { label: "Import manifests", value: "IMPORT_MANIFEST" },
  { label: "Other", value: "OTHER" },
  { label: "Performance profiles", value: "PERFORMANCE_PROFILE" },
  { label: "Repository checkpoints", value: "REPOSITORY_CHECKPOINT" },
  { label: "Verification evidence", value: "VERIFICATION_EVIDENCE" },
  { label: "Web research", value: "WEB_RESEARCH" }
];

export const ARTIFACT_SOURCE_KINDS: ReadonlyArray<{
  readonly label: string;
  readonly value: DevelopmentArtifactSourceKind;
}> = [
  { label: "Downloaded document", value: "DOWNLOADED_DOCUMENT" },
  { label: "Generated", value: "GENERATED" },
  { label: "Git commit", value: "GIT_COMMIT" },
  { label: "Local file", value: "LOCAL_FILE" },
  { label: "Other", value: "OTHER" },
  { label: "Web page", value: "WEB_PAGE" },
  { label: "Web search", value: "WEB_SEARCH" }
];

export const ARTIFACT_RELATIONS: readonly DevelopmentArtifactRelationKind[] = [
  "CONTAINS",
  "DERIVED_FROM",
  "DOCUMENTS",
  "EVIDENCES",
  "PRODUCED_BY_IMPORT",
  "REFERENCES",
  "SUPERSEDES"
];

export const RELATION_DIRECTIONS: readonly ArtifactRelationDirection[] = [
  "BOTH",
  "INCOMING",
  "OUTGOING"
];

export const PAGE_START = "__knowledge_page_start__";

export type SkillSummary = SkillSummaryFieldsFragment;
export type ArtifactSummary = ArtifactSummaryFieldsFragment;
export type SkillConnection = NonNullable<ProjectSkillsQuery["projectSkills"]>;
export type ProjectSkill = NonNullable<ProjectSkillQuery["projectSkill"]>;
export type ProjectSkillAsset = NonNullable<ProjectSkillAssetQuery["projectSkillAsset"]>;
export type GlobalSkillConnection = SkillsQuery["skills"];
export type GlobalSkill = NonNullable<SkillQuery["skill"]>;
export type GlobalSkillAsset = NonNullable<SkillAssetQuery["skillAsset"]>;
export type ArtifactConnection = NonNullable<ProjectArtifactsQuery["projectArtifacts"]>;
export type ProjectArtifact = NonNullable<ProjectArtifactQuery["projectArtifact"]>;
export type ProjectArtifactRelationships = NonNullable<
  ProjectArtifactRelationshipsQuery["projectArtifactRelationships"]
>;

export function preserveCollection<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  filterKey: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === filterKey
    ? previousData
    : undefined;
}

export function preserveDetail<T>(
  previousData: T | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  projectRef: string,
  identity: string
): T | undefined {
  return previousQueryKey?.[1] === projectRef && previousQueryKey?.[2] === identity
    ? previousData
    : undefined;
}

export function resetPagination(params: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(params);
  next.delete("after");
  next.delete("trail");
  return next;
}

export function nextPageParams(params: URLSearchParams, cursor: string): URLSearchParams {
  const next = new URLSearchParams(params);
  next.append("trail", params.get("after") ?? PAGE_START);
  next.set("after", cursor);
  return next;
}

export function previousPageParams(params: URLSearchParams): URLSearchParams {
  const next = new URLSearchParams(params);
  const trail = next.getAll("trail");
  const previous = trail.pop();
  next.delete("trail");
  trail.forEach((cursor) => next.append("trail", cursor));
  if (!previous || previous === PAGE_START) next.delete("after");
  else next.set("after", previous);
  return next;
}

export function applyFilters(
  params: URLSearchParams,
  filters: Readonly<Record<string, string>>
): URLSearchParams {
  const next = resetPagination(params);
  Object.entries(filters).forEach(([key, value]) => {
    const normalized = value.trim();
    if (normalized) next.set(key, normalized);
    else next.delete(key);
  });
  return next;
}

export function listLocation(pathname: string, params: URLSearchParams): string {
  const query = params.toString();
  return query ? `${pathname}?${query}` : pathname;
}

export function detailLocation(pathname: string, identity: string, returnTo: string): string {
  const query = new URLSearchParams({ returnTo }).toString();
  return `${pathname}/${encodeURIComponent(identity)}?${query}`;
}

export function childLocation(pathname: string, segment: string, identity: string, returnTo: string): string {
  const query = new URLSearchParams({ returnTo }).toString();
  return `${pathname}/${segment}/${encodeURIComponent(identity)}?${query}`;
}

export function safeKnowledgeReturnTo(
  value: string | null,
  fallback: string,
  knowledgeBasePath: string
): string {
  return value === knowledgeBasePath || value?.startsWith(`${knowledgeBasePath}/`)
    ? value
    : fallback;
}

export function humanized(value: string): string {
  return value.toLowerCase().replaceAll("_", " ");
}
