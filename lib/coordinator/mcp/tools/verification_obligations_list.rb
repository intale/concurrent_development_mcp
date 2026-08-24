# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class VerificationObligationsList < QueryTool
        tool_name "verification_obligations_list"
        title "List verification obligations"
        description "Page through latest available projected obligations, evidence progress, and outcomes with ANDed filters and no freshness gate."
        input_schema Schemas.verification_obligations_list
        query "queries.verification_obligations_list"
      end
    end
  end
end
