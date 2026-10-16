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
  ArtifactTable,
  ArtifactDetail,
  AvailableStale,
  PaginationControls,
  RelationshipTable,
  SkillAssetDetail,
  SkillTable,
  SkillDetail
} from "../src/knowledge/project-knowledge-view.js";

const projectRef = "project:concurrent_development_mcp";
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

test("Skill and Artifact collections use semantic tables with linked names and empty states", () => {
  const skillsMarkup = render(<SkillTable connection={{ nodes: [skillSummary], pageInfo: { endCursor: "next", hasNextPage: true } }} hrefFor={(skill) => `/skills/${skill.name}`} />);
  const artifactsMarkup = render(<ArtifactTable connection={{ nodes: [artifactSummary], pageInfo: { endCursor: "next", hasNextPage: true } }} hrefFor={(id) => `/artifacts/${id}`} />);

  assert.match(skillsMarkup, /Model coordination facts/);
  assert.match(skillsMarkup, /<caption class="visually-hidden">Project Skills<\/caption>/);
  assert.match(skillsMarkup, /<th scope="col">Name<\/th>/);
  assert.match(skillsMarkup, /<th scope="col">Scope<\/th>/);
  assert.match(skillsMarkup, /href="\/skills\/event-modeling"/);
  assert.match(skillsMarkup, /project:knowledge/);
  assert.doesNotMatch(skillsMarkup, /<article/);
  assert.match(artifactsMarkup, /Parent README/);
  assert.match(artifactsMarkup, /README.md/);
  assert.match(artifactsMarkup, /<caption class="visually-hidden">Development Artifacts<\/caption>/);
  assert.match(artifactsMarkup, /<th scope="col">Captured<\/th>/);
  assert.match(artifactsMarkup, /href="\/artifacts\//);
  assert.doesNotMatch(artifactsMarkup, /<article/);
  const empty = render(<SkillTable connection={{ nodes: [], pageInfo: { endCursor: null, hasNextPage: false } }} hrefFor={() => "/skill"} />);
  assert.match(empty, /<tbody><tr><td[^>]*(?:colSpan|colspan)="5"[^>]*>No Skills match this name\.<\/td><\/tr><\/tbody>/);
});

test("Skill, asset, Artifact, and relationship details stay on focused pages", () => {
  const skillMarkup = render(<SkillDetail assetHref={(path) => `/asset/${path}`} backTo="/skills?name=event" detail={skill} />);
  const assetMarkup = render(<SkillAssetDetail backTo="/skills/event-modeling" detail={asset} />);
  const artifactMarkup = render(<ArtifactDetail backTo="/artifacts?kind=docs" detail={artifact} relationshipsHref="/artifact/relationships" />);
  const relationshipMarkup = render(<RelationshipTable detail={relationships} peerHref={(id) => `/artifacts/${id}`} />);

  assert.match(skillMarkup, /data-markdown-preview=""/);
  assert.match(skillMarkup, /href="\/asset\/references\/example\.md"/);
  assert.match(skillMarkup, /<caption class="visually-hidden">Skill assets<\/caption>/);
  assert.match(skillMarkup, /<th scope="col">Executable<\/th>/);
  assert.match(skillMarkup, /Back to Skills/);
  assert.match(assetMarkup, /data-markdown-preview=""/);
  assert.match(assetMarkup, /Back to Skill/);
  assert.match(artifactMarkup, /View 1 relationships/);
  assert.match(artifactMarkup, /data-markdown-preview=""/);
  assert.doesNotMatch(artifactMarkup, /Child guide/);
  assert.match(relationshipMarkup, /Child guide/);
  assert.match(relationshipMarkup, /<caption class="visually-hidden">Artifact relationships<\/caption>/);
  assert.match(relationshipMarkup, /<th scope="col">Direction<\/th>/);
  assert.match(relationshipMarkup, /href="\/artifacts\//);
  assert.doesNotMatch(relationshipMarkup, /<article/);
});

test("Markdown assets use the shared isolated preview rather than light-DOM rendering", () => {
  const markdownAsset = {
    asset: {
      ...asset.asset,
      text: "| State | Owner |\n| --- | --- |\n| ready | agent |\n\n- [x] checked\n\n~~obsolete~~\n\n<script>alert('unsafe')</script>\n\n[unsafe](javascript:alert('unsafe'))"
    }
  } satisfies ProjectSkillAsset;
  const markup = render(<SkillAssetDetail backTo="/skills/event-modeling" detail={markdownAsset} />);

  assert.match(markup, /data-markdown-preview=""/);
  assert.match(markup, /aria-label="Markdown preview"/);
  assert.doesNotMatch(markup, /table-striped table-bordered|form-check-input/);
  assert.doesNotMatch(markup, /<script>/);
  assert.doesNotMatch(markup, /javascript:/);
});

test("knowledge pagination exposes Previous and Next controls", () => {
  const markup = render(
    <PaginationControls canPrevious nextCursor="next" onNext={() => undefined} onPrevious={() => undefined} />,
    `/projects/${projectRef}/skills`
  );
  assert.match(markup, /Previous/);
  assert.match(markup, /Next/);
  assert.match(markup, /aria-label="Collection pages"/);
});

test("filters, paging, details, and Back state remain URL-backed and Project-bounded", () => {
  const filtered = applyFilters(new URLSearchParams("after=old&trail=start"), { kind: " DOCUMENTATION ", labels: "docs", source: "" });
  const next = nextPageParams(filtered, "next-cursor");
  const previous = previousPageParams(next);
  const listPath = `/projects/${projectRef}/artifacts`;
  const detail = detailLocation(listPath, artifactSummary.id);

  assert.equal(filtered.get("kind"), "DOCUMENTATION");
  assert.equal(filtered.has("after"), false);
  assert.equal(next.get("after"), "next-cursor");
  assert.equal(previous.get("after"), null);
  assert.equal(detail, `${listPath}/${encodeURIComponent(artifactSummary.id)}`);
  assert.equal(new URL(detail, "https://coordinator.test").search, "");
  assert.equal(safeKnowledgeReturnTo(`${listPath}?kind=DOCUMENTATION`, listPath, `/projects/${projectRef}`), `${listPath}?kind=DOCUMENTATION`);
  assert.equal(safeKnowledgeReturnTo("https://example.test", listPath, `/projects/${projectRef}`), listPath);
});

test("available knowledge remains visible beside a localized refresh failure", () => {
  const markup = render(
    <><AvailableStale message="Projection endpoint unavailable" onRetry={() => undefined} /><SkillTable connection={{ nodes: [skillSummary], pageInfo: { endCursor: null, hasNextPage: false } }} hrefFor={() => "/skill"} /></>
  );
  assert.match(markup, /last available projection remains visible/);
  assert.match(markup, /Projection endpoint unavailable/);
  assert.match(markup, /event-modeling/);
});
