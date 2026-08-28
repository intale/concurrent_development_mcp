# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class RepositoryRegister < MutationTool
        tool_name "repository_register"
        title "Register a scoped repository identity"
        description <<~TEXT.squish
          Propose a caller-created UUIDv7 for one exact caller/user-chosen repository key and scope.
          A compatible existing tuple returns its canonical UUID. Actor labels, display names, paths,
          and remotes are caller-supplied attribution only; they do not prove identity or grant access.
        TEXT
        input_schema Schemas.repository_register
        operation "operations.submit_register_repository_task"
      end
    end
  end
end
