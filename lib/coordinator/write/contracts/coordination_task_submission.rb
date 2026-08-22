# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CoordinationTaskSubmission < Dry::Validation::Contract
      params do
        required(:event).value(Types.Instance(Events::CoordinationTaskSubmittedV1))
      end

      rule(:event) do
        event = value
        document = event.command_input

        unless event.tool_name == document.tool_name && event.command_id == document.command_id
          key.failure("must agree with the nested command document identity")
        end

        expected_digest = CanonicalJson.new.sha256(document.to_h)
        unless event.canonical_input_digest == expected_digest
          key.failure("must carry the canonical digest of the nested command document")
        end
      end
    end
  end
end
