# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CandidateList < QueryTool
        tool_name "candidate_list"
        title "List available Candidate checkpoints"
        description "List observed Candidate checkpoints for one Attempt in bounded cursor order."
        input_schema Schemas.candidate_list
        query "queries.candidate_list"
      end
    end
  end
end
