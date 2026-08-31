import { useEffect, useState } from "react";
import { Link, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { ProjectCatalogPage } from "./projects/project-catalog-page.js";
import { ProjectCoordinationPage } from "./coordination/project-coordination-page.js";
import { ProjectResourcesPage } from "./resources/project-resources-page.js";
import { ProjectKnowledgePage } from "./knowledge/project-knowledge-page.js";

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
      <nav className="app-header navbar navbar-expand bg-body">
        <div className="container-fluid">
          <ul className="navbar-nav">
            <li className="nav-item">
              <button
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

      <aside className="app-sidebar bg-body-secondary shadow" data-bs-theme="dark">
        <div className="sidebar-brand">
          <Link className="brand-link" to="/projects">
            <span className="brand-text fw-semibold">Coordinator</span>
          </Link>
        </div>
        <div className="sidebar-wrapper">
          <nav aria-label="Primary navigation" className="mt-2">
            <ul className="nav sidebar-menu flex-column" role="menu">
              <li className="nav-header">Coordination</li>
              <li className="nav-item">
                <Link
                  className={`nav-link ${location.pathname.startsWith("/projects") ? "active" : ""}`}
                  to="/projects"
                >
                  <i aria-hidden="true" className="nav-icon bi bi-folder2-open" />
                  <p>Projects</p>
                </Link>
              </li>
            </ul>
          </nav>
        </div>
      </aside>

      <main className="app-main">
        <Routes>
          <Route path="/projects" element={<ProjectCatalogPage />} />
          <Route path="/projects/:repositoryId/coordination" element={<ProjectCoordinationPage />} />
          <Route path="/projects/:repositoryId/resources" element={<ProjectResourcesPage />} />
          <Route path="/projects/:repositoryId/knowledge" element={<ProjectKnowledgePage />} />
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
