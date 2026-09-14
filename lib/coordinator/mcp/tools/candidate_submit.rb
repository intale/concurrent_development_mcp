# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CandidateSubmit < MutationTool
        tool_name "candidate_submit"
        title "Submit a development Candidate checkpoint"
        description "Submit one attributed Candidate commit with its exact work-intention observations, " \
                    "canonical change manifest, and optional build context. Every changed Resource must be " \
                    "covered for accountability; coverage does not promise conflict-free integration."
        input_schema Schemas.candidate_submit
        operation "operations.submit_candidate_task"
      end
    end
  end
end
