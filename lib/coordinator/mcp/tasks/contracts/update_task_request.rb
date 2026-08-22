# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    module Contracts
      class UpdateTaskRequest < Dry::Validation::Contract
        config.validate_keys = false

        params do
          required(:taskId).filled(Types::TaskId)
          required(:inputResponses).value(:hash)
          optional(:_meta).value(:hash)
        end
      end
    end
  end
end
