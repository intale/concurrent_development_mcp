import assert from "node:assert/strict";
import test from "node:test";
import type { ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  ArtifactSummary,
  ProjectArtifact,
  ProjectArtifactRelationships,
  ProjectSkill,
  ProjectSkillAsset,
  SkillSummary
} from "../src/knowledge/project-knowledge-model.js";
import {
  applyFilters,
  detailLocation,
  nextPageParams,
  previousPageParams,
  safeKnowledgeReturnTo
} from "../src/knowledge/project-knowledge-model.js";
import {
  ArtifactCards,
  ArtifactDetail,
  AvailableStale,
  KnowledgeNavigation,
  PaginationControls,
  RelationshipCards,
  SkillAssetDetail,
  SkillCards,
  SkillDetail
} from "../src/knowledge/project-knowledge-view.js";

const projectRef = "project-ref";
const scope = "project:knowledge";
const timestamp = "2026-08-31T12:00:00.000000Z";
const skillSummary = {
  id: `skill:v1:${"1".repeat(64)}`,
  name: "event-modeling",
  scope,
  revision: 2,
  description: "Model coordination facts",
  assetCount: 1,
  contentDigest: `sha256:${"1".repeat(64)}`,
  publishedAt: timestamp
} satisfies SkillSummary;
const skill = {
  skill: {
    ...skillSummary,
    instructions: "Given facts, when a command runs, then emit events.",
    assets: [{
      path: "references/example.md",
      mediaType: "text/markdown",
      executable: false,
      contentDigest: `sha256:${"2".repeat(64)}`,
      byteSize: 42
    }]
  }
} satisfies ProjectSkill;
const asset = {
  asset: {
    path: "references/example.md",
    revision: 2,
    encoding: "utf-8",
    mediaType: "text/markdown",
    executable: false,
    text: "Example content",
    base64: null,
    contentDigest: `sha256:${"2".repeat(64)}`,
    byteSize: 42
  }
} satisfies ProjectSkillAsset;
const artifactSummary = {
  id: `artifact:v1:${"a".repeat(64)}`,
  observationId: `artifact-observation:v1:${"a".repeat(64)}`,
  scope,
  title: "Parent README",
  kind: "DOCUMENTATION" as const,
  labels: ["docs"],
  mediaType: "text/markdown",
  encoding: "utf-8",
  contentDigest: `sha256:${"a".repeat(64)}`,
  byteSize: 15,
  classificationRevision: 2,
  classificationReason: "Current documentation",
  relationshipCount: 1,
  capturedAt: timestamp,
  observedAt: timestamp,
  classifiedAt: timestamp,
  source: { kind: "LOCAL_FILE" as const, locator: "README.md", revision: "a".repeat(40), observedAt: timestamp, collector: "agent/v1" }
} satisfies ArtifactSummary;
const artifact = {
  artifact: artifactSummary,
  content: {
    encoding: "utf-8",
    mediaType: "text/markdown",
    text: "# Parent README",
    base64: null,
    contentDigest: artifactSummary.contentDigest,
    byteSize: 15
  }
} satisfies ProjectArtifact;
const relationships = {
  artifact: artifactSummary,
  relationships: {
    nodes: [{
      id: `artifact-relation:v1:${"3".repeat(64)}`,
      direction: "OUTGOING" as const,
      relation: "CONTAINS" as const,
      displayRelation: "contains",
      peerKind: "artifact",
      peerId: `artifact:v1:${"b".repeat(64)}`,
      status: "active",
      targetStatus: "verified",
      targetName: null,
      targetScope: null,
      path: null,
      fragment: null,
      normalizedLocator: null,
      declaredAt: timestamp,
      peerArtifact: {
        ...artifactSummary,
        id: `artifact:v1:${"b".repeat(64)}`,
        observationId: `artifact-observation:v1:${"b".repeat(64)}`,
        title: "Child guide",
        source: { ...artifactSummary.source, locator: "docs/guide.md" }
      }
    }],
    pageInfo: { endCursor: "next-relation", hasNextPage: true }
  }
} satisfies ProjectArtifactRelationships;

function render(node: ReactNode, route = "/") {
  return renderToStaticMarkup(<MemoryRouter initialEntries={[route]}>{node}</MemoryRouter>);
}

test("focused Skill and Artifact collections lead with meaning and adjacent primary actions", () => {
  const skillsMarkup = render(<SkillCards connection={{ nodes: [skillSummary], pageInfo: { endCursor: "next", hasNextPage: true } }} hrefFor={(skill) => `/skills/${skill.name}`} />);
  const artifactsMarkup = render(<ArtifactCards connection={{ nodes: [artifactSummary], pageInfo: { endCursor: "next", hasNextPage: true } }} hrefFor={(id) => `/artifacts/${id}`} />);

  assert.match(skillsMarkup, /Model coordination facts/);
  assert.match(skillsMarkup, /View Skill/);
  assert.match(skillsMarkup, /col-12 col-xl-6/);
  assert.match(artifactsMarkup, /Parent README/);
  assert.match(artifactsMarkup, /README.md/);
  assert.match(artifactsMarkup, /View Artifact/);
});

test("Skill, asset, Artifact, and relationship details stay on focused pages", () => {
  const skillMarkup = render(<SkillDetail assetHref={(path) => `/asset/${path}`} backTo="/skills?name=event" detail={skill} />);
  const assetMarkup = render(<SkillAssetDetail backTo="/skills/event-modeling" detail={asset} />);
  const artifactMarkup = render(<ArtifactDetail backTo="/artifacts?kind=docs" detail={artifact} relationshipsHref="/artifact/relationships" />);
  const relationshipMarkup = render(<RelationshipCards detail={relationships} peerHref={(id) => `/artifacts/${id}`} />);

  assert.match(skillMarkup, /Given facts/);
  assert.match(skillMarkup, /View asset/);
  assert.match(skillMarkup, /Back to Skills/);
  assert.match(assetMarkup, /Example content/);
  assert.match(assetMarkup, /Back to Skill/);
  assert.match(artifactMarkup, /View 1 relationships/);
  assert.match(artifactMarkup, /<h1>Parent README<\/h1>/);
  assert.doesNotMatch(artifactMarkup, /Child guide/);
  assert.match(relationshipMarkup, /Child guide/);
  assert.match(relationshipMarkup, /View related Artifact/);
});

test("Knowledge subnavigation and recoverable pagination are explicit", () => {
  const markup = render(
    <><KnowledgeNavigation basePath={`/projects/${projectRef}/knowledge`} /><PaginationControls canPrevious nextCursor="next" onNext={() => undefined} onPrevious={() => undefined} /></>,
    `/projects/${projectRef}/knowledge/skills`
  );
  assert.match(markup, /aria-label="Knowledge views"/);
  assert.match(markup, /Skills/);
  assert.match(markup, /Development Artifacts/);
  assert.match(markup, /Previous/);
  assert.match(markup, /Next/);
});

test("filters, paging, details, and Back state remain URL-backed and Project-bounded", () => {
  const filtered = applyFilters(new URLSearchParams("after=old&trail=start"), { kind: " DOCUMENTATION ", labels: "docs", source: "" });
  const next = nextPageParams(filtered, "next-cursor");
  const previous = previousPageParams(next);
  const listPath = `/projects/${projectRef}/knowledge/artifacts`;
  const detail = detailLocation(listPath, artifactSummary.id, `${listPath}?${filtered.toString()}`);

  assert.equal(filtered.get("kind"), "DOCUMENTATION");
  assert.equal(filtered.has("after"), false);
  assert.equal(next.get("after"), "next-cursor");
  assert.equal(previous.get("after"), null);
  assert.match(detail, /returnTo=/);
  assert.equal(safeKnowledgeReturnTo(`${listPath}?kind=DOCUMENTATION`, listPath, `/projects/${projectRef}/knowledge`), `${listPath}?kind=DOCUMENTATION`);
  assert.equal(safeKnowledgeReturnTo("https://example.test", listPath, `/projects/${projectRef}/knowledge`), listPath);
});

test("available knowledge remains visible beside a localized refresh failure", () => {
  const markup = render(
    <><AvailableStale message="Projection endpoint unavailable" onRetry={() => undefined} /><SkillCards connection={{ nodes: [skillSummary], pageInfo: { endCursor: null, hasNextPage: false } }} hrefFor={() => "/skill"} /></>
  );
  assert.match(markup, /last available projection remains visible/);
  assert.match(markup, /Projection endpoint unavailable/);
  assert.match(markup, /event-modeling/);
});
