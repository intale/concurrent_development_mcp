import { Fragment, useEffect, useRef, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation, useMatch } from "react-router-dom";
import { PROJECT_NAVIGATION, projectPath } from "./navigation.js";
import { CommandReceiptsPage } from "./audit/command-receipts-page.js";
import { CoordinationChangeSetsPage } from "./coordination/coordination-change-sets-page.js";
import { CoordinationDependenciesPage } from "./coordination/coordination-dependencies-page.js";
import { CoordinationWorkItemsPage } from "./coordination/coordination-work-items-page.js";
import {
  ProjectArtifactRelationshipsPage,
  ProjectArtifactsPage,
  ProjectSkillsPage
} from "./knowledge/project-knowledge-page.js";
import { GlobalSkillsPage } from "./knowledge/global-skills-page.js";
import {
  ProjectGovernanceChoicesPage,
  ProjectGovernanceDecisionsPage,
  ProjectGovernanceGuidancePage,
  ProjectGovernanceImpactsPage
} from "./governance/project-governance-page.js";
import {
  ProjectDeliveryCandidatesPage,
  ProjectDeliveryMergesPage,
  ProjectDeliveryObligationsPage,
  ProjectDeliveryReleasesPage
} from "./delivery/project-delivery-page.js";
import { OperationBatchesPage } from "./operations/operation-batches-page.js";
import { ProjectCatalogPage } from "./projects/project-catalog-page.js";
import { ProjectOverviewPage } from "./projects/project-overview-page.js";
import { ProjectWorkspaceShell } from "./projects/project-workspace-shell.js";
import {
  ProjectResourceInventoryPage,
  ProjectResourceWorkIntentionsPage
} from "./resources/project-resources-page.js";

const COMPACT_NAVIGATION_QUERY = "(max-width: 991.98px)";
const FOCUSABLE_NAVIGATION_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])"
].join(",");

export type ContainedNavigationAction = "close" | "focus-first" | "focus-last" | null;

export function navigationIsExpanded(
  compact: boolean,
  sidebarOpen: boolean,
  sidebarCollapsed: boolean
): boolean {
  return compact ? sidebarOpen : !sidebarCollapsed;
}

export function containedNavigationAction(
  key: string,
  shiftKey: boolean,
  activeIndex: number,
  itemCount: number
): ContainedNavigationAction {
  if (key === "Escape") return "close";
  if (key !== "Tab" || itemCount === 0) return null;
  if (activeIndex < 0) return "focus-first";
  if (shiftKey && activeIndex === 0) return "focus-last";
  if (!shiftKey && activeIndex === itemCount - 1) return "focus-first";
  return null;
}

function compactNavigationMatches(): boolean {
  return typeof window !== "undefined" && window.matchMedia(COMPACT_NAVIGATION_QUERY).matches;
}

export function App() {
  const location = useLocation();
  const projectMatch = useMatch("/projects/:projectRef/*");
  const activeProjectPath = projectMatch ? projectPath(projectMatch.params.projectRef ?? "") : null;
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [compactNavigation, setCompactNavigation] = useState(compactNavigationMatches);
  const headerRef = useRef<HTMLElement>(null);
  const mainRef = useRef<HTMLElement>(null);
  const footerRef = useRef<HTMLElement>(null);
  const sidebarRef = useRef<HTMLElement>(null);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const restoreFocusRef = useRef(false);

  useEffect(() => {
    const body = document.body;
    const layoutClasses = ["layout-fixed", "sidebar-expand-lg", "bg-body-tertiary"];
    body.classList.add(...layoutClasses);
    body.classList.toggle("sidebar-collapse", sidebarCollapsed);
    body.classList.toggle("sidebar-open", sidebarOpen);

    return () => {
      body.classList.remove(...layoutClasses, "sidebar-collapse", "sidebar-open");
    };
  }, [sidebarCollapsed, sidebarOpen]);

  useEffect(() => {
    const query = window.matchMedia(COMPACT_NAVIGATION_QUERY);
    const updateNavigationMode = (event: MediaQueryListEvent) => {
      setCompactNavigation(event.matches);
      if (!event.matches) {
        restoreFocusRef.current = false;
        setSidebarOpen(false);
      }
    };
    setCompactNavigation(query.matches);
    query.addEventListener("change", updateNavigationMode);
    return () => query.removeEventListener("change", updateNavigationMode);
  }, []);

  useEffect(() => {
    setSidebarOpen(false);
    restoreFocusRef.current = false;
  }, [location.pathname]);

  useEffect(() => {
    const sidebar = sidebarRef.current;
    const header = headerRef.current;
    const main = mainRef.current;
    const footer = footerRef.current;
    if (!sidebar || !header || !main || !footer) return;

    if (compactNavigation && sidebarOpen) {
      returnFocusRef.current = document.activeElement instanceof HTMLElement &&
        document.activeElement !== document.body
        ? document.activeElement
        : toggleRef.current;
    }
    sidebar.inert = compactNavigation && !sidebarOpen;
    header.inert = compactNavigation && sidebarOpen;
    main.inert = compactNavigation && sidebarOpen;
    footer.inert = compactNavigation && sidebarOpen;

    if (!compactNavigation || !sidebarOpen) {
      if (restoreFocusRef.current) {
        (returnFocusRef.current ?? toggleRef.current)?.focus();
        restoreFocusRef.current = false;
      }
      return;
    }

    const focusable = Array.from(
      sidebar.querySelectorAll<HTMLElement>(FOCUSABLE_NAVIGATION_SELECTOR)
    );
    const currentLink = sidebar.querySelector<HTMLElement>("[aria-current='page']");
    (currentLink ?? focusable[0])?.focus();

    const containFocus = (event: KeyboardEvent) => {
      const items = Array.from(
        sidebar.querySelectorAll<HTMLElement>(FOCUSABLE_NAVIGATION_SELECTOR)
      );
      const action = containedNavigationAction(
        event.key,
        event.shiftKey,
        items.indexOf(document.activeElement as HTMLElement),
        items.length
      );
      if (action === "close") {
        event.preventDefault();
        restoreFocusRef.current = true;
        setSidebarOpen(false);
      } else if (action === "focus-first" || action === "focus-last") {
        event.preventDefault();
        items[action === "focus-first" ? 0 : items.length - 1]?.focus();
      }
    };
    document.addEventListener("keydown", containFocus);
    return () => document.removeEventListener("keydown", containFocus);
  }, [compactNavigation, sidebarOpen]);

  const toggleSidebar = () => {
    if (compactNavigation) {
      if (sidebarOpen) restoreFocusRef.current = true;
      setSidebarOpen((current) => !current);
    } else {
      setSidebarCollapsed((current) => !current);
    }
  };

  const closeCompactNavigation = () => {
    restoreFocusRef.current = true;
    setSidebarOpen(false);
  };

  return (
    <div className="app-wrapper">
      <a className="visually-hidden-focusable" href="#main-content">Skip to main content</a>
      <nav aria-label="Application controls" className="app-header navbar navbar-expand bg-body" ref={headerRef}>
        <div className="container-fluid">
          <ul className="navbar-nav">
            <li className="nav-item">
              <button
                aria-controls="primary-sidebar"
                aria-expanded={navigationIsExpanded(
                  compactNavigation,
                  sidebarOpen,
                  sidebarCollapsed
                )}
                aria-label="Toggle navigation"
                className="nav-link"
                onClick={toggleSidebar}
                ref={toggleRef}
                type="button"
              >
                <i aria-hidden="true" className="bi bi-list" />
              </button>
            </li>
          </ul>
          <span className="navbar-text"><span className="fw-semibold me-3">Development coordinator</span><span className="badge text-bg-light border">Read-only</span></span>
        </div>
      </nav>

      <aside
        aria-hidden={compactNavigation && !sidebarOpen ? true : undefined}
        className="app-sidebar bg-body-secondary shadow"
        data-bs-theme="dark"
        id="primary-sidebar"
        ref={sidebarRef}
      >
        <div className="sidebar-brand">
          <Link className="brand-link" to="/projects">
            <span className="brand-text fw-semibold">Coordinator</span>
          </Link>
        </div>
        <div className="sidebar-wrapper">
          <nav aria-label="Primary navigation" className="mt-2">
            <ul className="nav sidebar-menu flex-column">
              <li className="nav-header">Workspace</li>
              <li className="nav-item">
                <NavLink
                  className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`}
                  end
                  to="/projects"
                >
                  <i aria-hidden="true" className="nav-icon bi bi-folder2-open" />
                  <p>Projects</p>
                </NavLink>
              </li>
              {activeProjectPath ? PROJECT_NAVIGATION.map((group) => (
                <Fragment key={group.label}>
                  <li className="nav-header">{group.label}</li>
                  {group.items.map((item) => (
                    <li className="nav-item" key={item.path}>
                      <NavLink className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`} end={item.path === ""} to={`${activeProjectPath}${item.path}`}>
                        <i aria-hidden="true" className={`nav-icon bi ${item.icon}`} /><p>{item.label}</p>
                      </NavLink>
                    </li>
                  ))}
                </Fragment>
              )) : null}
              <li className="nav-header">All projects</li>
              <li className="nav-item">
                <NavLink
                  className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`}
                  to="/skills"
                >
                  <i aria-hidden="true" className="nav-icon bi bi-journal-code" />
                  <p>All skills</p>
                </NavLink>
              </li>
              <li className="nav-item">
                <NavLink
                  className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`}
                  to="/audit/command-receipts"
                >
                  <i aria-hidden="true" className="nav-icon bi bi-receipt" />
                  <p>Command receipts</p>
                </NavLink>
              </li>
              <li className="nav-item">
                <NavLink
                  className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`}
                  to="/operations/batches"
                >
                  <i aria-hidden="true" className="nav-icon bi bi-stack" />
                  <p>Operation batches</p>
                </NavLink>
              </li>
            </ul>
          </nav>
        </div>
      </aside>

      <main className="app-main" id="main-content" ref={mainRef}>
        <Routes>
          <Route path="/projects" element={<ProjectCatalogPage />} />
          <Route path="/skills" element={<GlobalSkillsPage />} />
          <Route path="/skills/:skillId" element={<GlobalSkillsPage />} />
          <Route path="/skills/:skillId/assets/*" element={<GlobalSkillsPage />} />
          <Route path="/audit/command-receipts" element={<CommandReceiptsPage />} />
          <Route path="/audit/command-receipts/:commandId" element={<CommandReceiptsPage />} />
          <Route path="/operations/batches" element={<OperationBatchesPage />} />
          <Route path="/operations/batches/:batchId" element={<OperationBatchesPage />} />
          <Route path="/projects/:projectRef" element={<ProjectWorkspaceShell />}>
            <Route index element={<ProjectOverviewPage />} />
            <Route path="change-sets" element={<CoordinationChangeSetsPage />} />
            <Route path="change-sets/:changeSetId" element={<CoordinationChangeSetsPage />} />
            <Route path="work-items" element={<CoordinationWorkItemsPage />} />
            <Route path="work-items/:workItemId" element={<CoordinationWorkItemsPage />} />
            <Route path="dependencies" element={<CoordinationDependenciesPage />} />
            <Route path="dependencies/:dependencyId" element={<CoordinationDependenciesPage />} />
            <Route path="resources" element={<ProjectResourceInventoryPage />} />
            <Route path="resources/:resourceId" element={<ProjectResourceInventoryPage />} />
            <Route path="work-intentions" element={<ProjectResourceWorkIntentionsPage />} />
            <Route path="work-intentions/:intentionId" element={<ProjectResourceWorkIntentionsPage />} />
            <Route path="skills" element={<ProjectSkillsPage />} />
            <Route path="skills/:skillName" element={<ProjectSkillsPage />} />
            <Route path="skills/:skillName/assets/*" element={<ProjectSkillsPage />} />
            <Route path="artifacts" element={<ProjectArtifactsPage />} />
            <Route path="artifacts/:artifactId" element={<ProjectArtifactsPage />} />
            <Route path="artifacts/:artifactId/relationships" element={<ProjectArtifactRelationshipsPage />} />
            <Route path="decisions" element={<ProjectGovernanceDecisionsPage />} />
            <Route path="decisions/:decisionId" element={<ProjectGovernanceDecisionsPage />} />
            <Route path="guidance" element={<ProjectGovernanceGuidancePage />} />
            <Route path="guidance/:messageId" element={<ProjectGovernanceGuidancePage />} />
            <Route path="choices" element={<ProjectGovernanceChoicesPage />} />
            <Route path="choices/:choiceId" element={<ProjectGovernanceChoicesPage />} />
            <Route path="impacts" element={<ProjectGovernanceImpactsPage />} />
            <Route path="impacts/:assessmentId" element={<ProjectGovernanceImpactsPage />} />
            <Route path="candidates" element={<ProjectDeliveryCandidatesPage />} />
            <Route path="candidates/:candidateId" element={<ProjectDeliveryCandidatesPage />} />
            <Route path="obligations" element={<ProjectDeliveryObligationsPage />} />
            <Route path="obligations/:obligationId" element={<ProjectDeliveryObligationsPage />} />
            <Route path="merge-snapshots" element={<ProjectDeliveryMergesPage />} />
            <Route path="merge-snapshots/:mergeSnapshotId" element={<ProjectDeliveryMergesPage />} />
            <Route path="release-sets" element={<ProjectDeliveryReleasesPage />} />
            <Route path="release-sets/:releaseSetId" element={<ProjectDeliveryReleasesPage />} />
          </Route>
          <Route path="*" element={<Navigate replace to="/projects" />} />
        </Routes>
      </main>

      <footer className="app-footer" ref={footerRef}>
        <strong>Coordinator</strong> · Read-only. Updates appear as events are processed.
      </footer>
      <button
        aria-label="Close navigation"
        aria-hidden={!compactNavigation || !sidebarOpen}
        className="sidebar-overlay border-0"
        onClick={closeCompactNavigation}
        tabIndex={compactNavigation && sidebarOpen ? 0 : -1}
        type="button"
      />
    </div>
  );
}
