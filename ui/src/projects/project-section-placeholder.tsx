import { useEffect, useRef } from "react";
import { useProjectWorkspace } from "./project-workspace-shell.js";

export interface ProjectSectionPlaceholderProps {
  readonly description: string;
  readonly title: string;
}

export function ProjectSectionPlaceholder({ description, title }: ProjectSectionPlaceholderProps) {
  const { project } = useProjectWorkspace();
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    document.title = `${title} · ${project.displayLabel} · Coordinator`;
    headingRef.current?.focus();
  }, [project.projectRef, title]);

  return (
    <section aria-labelledby="project-section-heading">
      <h2 className="h3" id="project-section-heading" ref={headingRef} tabIndex={-1}>{title}</h2>
      <div className="card">
        <div className="card-body">
          <p className="mb-0">{description}</p>
        </div>
      </div>
    </section>
  );
}
