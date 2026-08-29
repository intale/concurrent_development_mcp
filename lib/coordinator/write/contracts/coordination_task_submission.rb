# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CoordinationTaskSubmission < Dry::Validation::Contract
      Submission = Types.Instance(Events::CoordinationTaskSubmittedV1) |
                   Types.Instance(Events::CoordinationTaskSubmittedV2)

      params do
        required(:event).value(Submission)
      end

      rule(:event) do
        event = value
        document = event.command_input

        unless event.tool_name == document.tool_name && event.command_id == document.command_id
          key.failure("must agree with the nested command document identity")
        end

        next unless event.is_a?(Events::CoordinationTaskSubmittedV1)

        expected_digest = CanonicalJson.new.sha256(document.to_h)
        key.failure("must carry the canonical digest of the nested command document") unless
          event.canonical_input_digest == expected_digest
      end
    end
  end
end
