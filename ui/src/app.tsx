import { useEffect, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation } from "react-router-dom";
import { CommandReceiptsPage } from "./audit/command-receipts-page.js";
import { CoordinationChangeSetsPage } from "./coordination/coordination-change-sets-page.js";
import { CoordinationDependenciesPage } from "./coordination/coordination-dependencies-page.js";
import { CoordinationWorkItemsPage } from "./coordination/coordination-work-items-page.js";
import {
  ProjectArtifactRelationshipsPage,
  ProjectArtifactsPage,
  ProjectSkillsPage
} from "./knowledge/project-knowledge-page.js";
import {
  ProjectGovernanceChoicesPage,
  ProjectGovernanceDecisionsPage,
  ProjectGovernanceGuidancePage,
  ProjectGovernanceImpactsPage
} from "./governance/project-governance-page.js";
import { OperationBatchesPage } from "./operations/operation-batches-page.js";
import { ProjectCatalogPage } from "./projects/project-catalog-page.js";
import { ProjectOverviewPage } from "./projects/project-overview-page.js";
import { ProjectSectionPlaceholder } from "./projects/project-section-placeholder.js";
import { ProjectWorkspaceShell } from "./projects/project-workspace-shell.js";
import {
  ProjectResourceInventoryPage,
  ProjectResourceLeasesPage
} from "./resources/project-resources-page.js";

export function App() {
  const location = useLocation();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);

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
    setSidebarOpen(false);
  }, [location.pathname]);

  const toggleSidebar = () => {
    if (window.matchMedia("(max-width: 991.98px)").matches) {
      setSidebarOpen((current) => !current);
    } else {
      setSidebarCollapsed((current) => !current);
    }
  };

  return (
    <div className="app-wrapper">
      <a className="visually-hidden-focusable" href="#main-content">Skip to main content</a>
      <nav className="app-header navbar navbar-expand bg-body">
        <div className="container-fluid">
          <ul className="navbar-nav">
            <li className="nav-item">
              <button
                aria-controls="primary-sidebar"
                aria-expanded={sidebarOpen || !sidebarCollapsed}
                aria-label="Toggle navigation"
                className="nav-link"
                onClick={toggleSidebar}
                type="button"
              >
                <i aria-hidden="true" className="bi bi-list" />
              </button>
            </li>
          </ul>
          <span className="navbar-text small text-body-secondary">Latest available projections</span>
        </div>
      </nav>

      <aside className="app-sidebar bg-body-secondary shadow" data-bs-theme="dark" id="primary-sidebar">
        <div className="sidebar-brand">
          <Link className="brand-link" to="/projects">
            <span className="brand-text fw-semibold">Coordinator</span>
          </Link>
        </div>
        <div className="sidebar-wrapper">
          <nav aria-label="Primary navigation" className="mt-2">
            <ul className="nav sidebar-menu flex-column">
              <li className="nav-header">Coordination</li>
              <li className="nav-item">
                <NavLink
                  className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`}
                  to="/projects"
                >
                  <i aria-hidden="true" className="nav-icon bi bi-folder2-open" />
                  <p>Projects</p>
                </NavLink>
              </li>
              <li className="nav-header">Global views</li>
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

      <main className="app-main" id="main-content">
        <Routes>
          <Route path="/projects" element={<ProjectCatalogPage />} />
          <Route path="/audit/command-receipts" element={<CommandReceiptsPage />} />
          <Route path="/audit/command-receipts/:commandId" element={<CommandReceiptsPage />} />
          <Route path="/operations/batches" element={<OperationBatchesPage />} />
          <Route path="/operations/batches/:batchId" element={<OperationBatchesPage />} />
          <Route path="/projects/:projectRef" element={<ProjectWorkspaceShell />}>
            <Route index element={<ProjectOverviewPage />} />
            <Route path="coordination" element={<Navigate replace to="change-sets" />} />
            <Route path="coordination/change-sets" element={<CoordinationChangeSetsPage />} />
            <Route path="coordination/change-sets/:changeSetId" element={<CoordinationChangeSetsPage />} />
            <Route path="coordination/work-items" element={<CoordinationWorkItemsPage />} />
            <Route path="coordination/work-items/:workItemId" element={<CoordinationWorkItemsPage />} />
            <Route path="coordination/dependencies" element={<CoordinationDependenciesPage />} />
            <Route path="coordination/dependencies/:dependencyId" element={<CoordinationDependenciesPage />} />
            <Route path="resources" element={<Navigate replace to="inventory" />} />
            <Route path="resources/inventory" element={<ProjectResourceInventoryPage />} />
            <Route path="resources/inventory/:resourceId" element={<ProjectResourceInventoryPage />} />
            <Route path="resources/leases" element={<ProjectResourceLeasesPage />} />
            <Route path="resources/leases/:leaseId" element={<ProjectResourceLeasesPage />} />
            <Route path="knowledge" element={<Navigate replace to="skills" />} />
            <Route path="knowledge/skills" element={<ProjectSkillsPage />} />
            <Route path="knowledge/skills/:skillName" element={<ProjectSkillsPage />} />
            <Route path="knowledge/skills/:skillName/assets/*" element={<ProjectSkillsPage />} />
            <Route path="knowledge/artifacts" element={<ProjectArtifactsPage />} />
            <Route path="knowledge/artifacts/:artifactId" element={<ProjectArtifactsPage />} />
            <Route path="knowledge/artifacts/:artifactId/relationships" element={<ProjectArtifactRelationshipsPage />} />
            <Route path="governance" element={<Navigate replace to="decisions" />} />
            <Route path="governance/decisions" element={<ProjectGovernanceDecisionsPage />} />
            <Route path="governance/decisions/:decisionId" element={<ProjectGovernanceDecisionsPage />} />
            <Route path="governance/guidance" element={<ProjectGovernanceGuidancePage />} />
            <Route path="governance/guidance/:messageId" element={<ProjectGovernanceGuidancePage />} />
            <Route path="governance/choices" element={<ProjectGovernanceChoicesPage />} />
            <Route path="governance/choices/:choiceId" element={<ProjectGovernanceChoicesPage />} />
            <Route path="governance/impacts" element={<ProjectGovernanceImpactsPage />} />
            <Route path="governance/impacts/:assessmentId" element={<ProjectGovernanceImpactsPage />} />
            <Route
              path="delivery"
              element={(
                <ProjectSectionPlaceholder
                  description="Project Candidates, verification, merge evidence, and releases belong in focused Delivery routes."
                  title="Delivery"
                />
              )}
            />
          </Route>
          <Route path="*" element={<Navigate replace to="/projects" />} />
        </Routes>
      </main>

      <footer className="app-footer">
        <strong>Coordinator</strong> read-only projection browser
      </footer>
      <button
        aria-label="Close navigation"
        className="sidebar-overlay border-0"
        onClick={() => setSidebarOpen(false)}
        type="button"
      />
    </div>
  );
}
