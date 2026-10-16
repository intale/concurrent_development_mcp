import { Link, useLocation } from "react-router-dom";
import type { LinkProps } from "react-router-dom";

/** Scopes are exact identities, not slugs: encode a segment once, preserving readable colons. */
export function projectPath(scope: string): string {
  return `/projects/${encodeURIComponent(scope).replaceAll("%3A", ":")}`;
}

export function detailPath(collection: string, identity: string): string {
  return `${collection}/${encodeURIComponent(identity)}`;
}

/** Back context belongs to browser history, not an ever-growing URL document. */
export function ContextLink({ state, ...props }: LinkProps) {
  const location = useLocation();
  const nextState = navigationStateForLink(
    `${location.pathname}${location.search}`,
    typeof props.to === "string" ? props.to : "",
    location.state
  );
  return <Link {...props} state={state ?? nextState} />;
}

export function navigationReturnTo(state: unknown): string | null {
  return navigationTrail(state)[0] ?? null;
}

export function navigationStateForLink(current: string, target: string, state: unknown): { readonly backTrail: readonly string[] } {
  const trail = navigationTrail(state);
  return { backTrail: target === trail[0] ? trail.slice(1) : [current, ...trail].slice(0, 8) };
}

function navigationTrail(state: unknown): readonly string[] {
  if (typeof state !== "object" || state === null || !("backTrail" in state) || !Array.isArray(state.backTrail)) return [];
  return state.backTrail.filter((value: unknown): value is string => (
    typeof value === "string" && value.startsWith("/") && !value.startsWith("//") && !/[\r\n\\]/.test(value)
  )).slice(0, 8);
}

export interface ProjectNavigationGroup {
  readonly label: string;
  readonly items: readonly { readonly path: string; readonly label: string; readonly icon: string }[];
}

export const PROJECT_NAVIGATION: readonly ProjectNavigationGroup[] = [
  { label: "Project work", items: [
    { path: "", label: "Overview", icon: "bi-house-door" },
    { path: "/work-items", label: "Work items", icon: "bi-list-task" },
    { path: "/change-sets", label: "Change sets", icon: "bi-layers" },
    { path: "/dependencies", label: "Dependencies", icon: "bi-diagram-3" },
    { path: "/resources", label: "Resources", icon: "bi-file-earmark-code" },
    { path: "/work-intentions", label: "Work intentions", icon: "bi-people" }
  ] },
  { label: "Project knowledge", items: [
    { path: "/skills", label: "Skills", icon: "bi-journal-code" },
    { path: "/artifacts", label: "Development artifacts", icon: "bi-archive" },
    { path: "/decisions", label: "Decisions", icon: "bi-signpost-split" },
    { path: "/guidance", label: "Guidance", icon: "bi-chat-left-text" },
    { path: "/choices", label: "Agent choices", icon: "bi-check2-square" },
    { path: "/impacts", label: "Decision impacts", icon: "bi-arrow-left-right" }
  ] },
  { label: "Project delivery", items: [
    { path: "/candidates", label: "Checkpoints", icon: "bi-bookmark-check" },
    { path: "/obligations", label: "Verification", icon: "bi-shield-check" },
    { path: "/merge-snapshots", label: "Merge snapshots", icon: "bi-git" },
    { path: "/release-sets", label: "Release sets", icon: "bi-box-seam" }
  ] }
] as const;
