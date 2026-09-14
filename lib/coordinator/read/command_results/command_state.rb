# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class CommandState < Value
      attribute :command_id, Types::CommandId
      attribute :request_id, Types::RequestId
      attribute :tool_name, Types::CoordinationToolName
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :status, Types::String.enum("registered", "succeeded", "rejected")

      def self.reduce(events:, payloads:, contract: Coordinator::Write::Contracts::CommandHistory.new)
        validation = contract.call(events: payloads)
        raise InvalidProjectionSource, validation.errors.to_h.inspect if validation.failure?

        registration = payloads.first
        terminal = payloads.last
        status = case terminal
                 when Coordinator::Write::Events::CommandSucceededV1 then "succeeded"
                 when Coordinator::Write::Events::CommandRejectedV1,
                      Coordinator::Write::Events::CommandRejectedV2 then "rejected"
                 else "registered"
                 end
        new(
          command_id: registration.command_id,
          request_id: registration.request_id,
          tool_name: registration.tool_name,
          canonical_input_digest: events.first.metadata.fetch("canonical_input_digest"),
          status:
        )
      end

      def terminal?
        status != "registered"
      end

      def rejected?
        status == "rejected"
      end
    end
  end
end
