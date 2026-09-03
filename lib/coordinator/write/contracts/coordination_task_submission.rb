# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CoordinationTaskSubmission < Dry::Validation::Contract
      params do
        required(:event).value(
          Types.Instance(Events::CoordinationTaskSubmittedV2) |
          Types.Instance(Events::CoordinationTaskSubmittedV3)
        )
      end

      rule(:event) do
        event = value
        document = event.command_input

        unless event.tool_name == document.tool_name && event.command_id == document.command_id
          key.failure("must agree with the nested command document identity")
        end
      end
    end
  end
end
