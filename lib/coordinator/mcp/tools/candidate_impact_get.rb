# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class CandidateImpactGet < QueryTool
        tool_name "candidate_impact_get"
        title "Get potential Candidate impacts"
        description "Page through latest available incoming or outgoing potential Candidate relationships with exact projected evidence and no freshness gate."
        input_schema Schemas.candidate_impact_get
        query "queries.candidate_impact_get"
      end
    end
  end
end
