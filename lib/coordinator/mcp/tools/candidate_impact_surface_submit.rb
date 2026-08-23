# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CandidateImpactSurfaceSubmit < MutationTool
        tool_name "candidate_impact_surface_submit"
        title "Submit attributed Candidate impact evidence"
        description "Attach one bounded attributed semantic-impact surface to an exact Candidate head and evidence digest. Authoritative event-store facts reject stale or duplicate submissions."
        input_schema Schemas.candidate_impact_surface_submit
        operation "operations.submit_candidate_impact_surface_task"
      end
    end
  end
end
