Feature: Inspect current project Skills and Development Artifacts
  The read-only browser presents focused latest-projection views for one exact Project scope.

  Rule: Skill browsing exposes only the current revision

    @UI-GWT-08
    Scenario: Current Skill instructions and assets hide obsolete revision content
      Given projected knowledge rows contain current and obsolete revisions of one Skill
      When the browser opens the focused projected Skill detail
      Then only the current Skill instructions and assets are presented

  Rule: Artifact navigation follows only active semantic relationships

    @UI-GWT-09
    Scenario: Parent and child artifacts remain navigable in both directions
      Given projected knowledge rows contain related parent and child artifacts with a superseded edge
      When the browser opens the focused relationship views for both projected Artifacts
      Then the parent and child are mutually navigable without the superseded edge
