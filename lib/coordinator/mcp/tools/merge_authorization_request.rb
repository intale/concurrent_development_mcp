# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class MergeAuthorizationRequest < MutationTool
        tool_name "merge_authorization_request"
        title "Request authorization for an exact merge snapshot"
        description "Evaluate exact snapshot, target-base, policy, Candidate, and obligation evidence " \
                    "against authoritative event-store facts. Grants and denials are durable decisions."
        input_schema Schemas.merge_authorization_request
        operation "operations.submit_request_merge_authorization_task"
      end
    end
  end
end
