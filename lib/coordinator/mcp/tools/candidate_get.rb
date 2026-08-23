# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CandidateGet < QueryTool
        tool_name "candidate_get"
        title "Get available Candidate evidence"
        description "Read every currently observed Candidate evidence component without a freshness gate."
        input_schema Schemas.candidate_get
        query "queries.candidate_get"
      end
    end
  end
end
