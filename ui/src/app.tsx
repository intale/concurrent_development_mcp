import { useEffect, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation } from "react-router-dom";
import { CommandReceiptsPage } from "./audit/command-receipts-page.js";
import { OperationBatchesPage } from "./operations/operation-batches-page.js";
import { ProjectCatalogPage } from "./projects/project-catalog-page.js";
import { ProjectOverviewPage } from "./projects/project-overview-page.js";
import { ProjectSectionPlaceholder } from "./projects/project-section-placeholder.js";
import { ProjectWorkspaceShell } from "./projects/project-workspace-shell.js";

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
            <Route
              path="coordination"
              element={(
                <ProjectSectionPlaceholder
                  description="Scheduled ChangeSets, WorkItems, dependencies, Attempts, and checkpoints belong in this focused Project route."
                  title="Coordination"
                />
              )}
            />
            <Route
              path="resources"
              element={(
                <ProjectSectionPlaceholder
                  description="Repository resources and factual active leases belong in this focused Project route."
                  title="Resources"
                />
              )}
            />
            <Route
              path="knowledge"
              element={(
                <ProjectSectionPlaceholder
                  description="Project-scoped Skills and Development Artifacts belong in focused Knowledge routes."
                  title="Knowledge"
                />
              )}
            />
            <Route
              path="governance"
              element={(
                <ProjectSectionPlaceholder
                  description="Project Decisions, Guidance, and AgentChoices belong in focused Governance routes."
                  title="Governance"
                />
              )}
            />
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
