# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class RepositoryRegister < MutationTool
        tool_name "repository_register"
        title "Register a scoped repository identity"
        description <<~TEXT.squish
          Register one caller-created UUIDv7 as the canonical repository identity under an exact
          project/workspace scope. Display names, paths, and remotes are attributed metadata only.
        TEXT
        input_schema Schemas.repository_register
        operation "operations.submit_register_repository_task"
      end
    end
  end
end
