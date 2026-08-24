# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ReleaseRepositoryIntegrationRecord < MutationTool
        tool_name "release_repository_integration_record"
        title "Record a ReleaseSet repository integration attempt"
        description "Record attributed success or failure evidence for the next ordered ReleaseSet member."
        input_schema Schemas.release_repository_integration_record
        operation "operations.submit_record_repository_integration_task"
      end
    end
  end
end
