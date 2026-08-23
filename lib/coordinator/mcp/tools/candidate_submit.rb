# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CandidateSubmit < MutationTool
        tool_name "candidate_submit"
        title "Submit a development Candidate checkpoint"
        description "Submit one attributed Candidate commit with its exact lease observations, " \
                    "canonical change manifest, and optional build context. Authoritative event-store " \
                    "facts reject stale or unauthorized submissions."
        input_schema Schemas.candidate_submit
        operation "operations.submit_candidate_task"
      end
    end
  end
end
