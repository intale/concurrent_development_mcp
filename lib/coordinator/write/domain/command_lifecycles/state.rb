# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CommandLifecycles
      class State < Value
        attribute :command_id, Types::CommandId.optional
        attribute :request_id, Types::RequestId.optional
        attribute :tool_name, Types::CoordinationToolName.optional
        attribute :canonical_input_digest, Types::Sha256Digest.optional
        attribute :status, Types::String.enum("absent", "registered", "succeeded", "rejected")
        attribute :rejection_code, Types::Identifier.optional
        attribute :rejection_reason, Types::String.optional
        attribute :rejection_retryable, Types::Strict::Bool.optional

        def self.initial
          new(
            command_id: nil,
            request_id: nil,
            tool_name: nil,
            canonical_input_digest: nil,
            status: "absent",
            rejection_code: nil,
            rejection_reason: nil,
            rejection_retryable: nil
          )
        end

        def self.reduce(events, canonical_input_digests: [], contract: Contracts::CommandHistory.new)
          validation = contract.call(events:)
          raise InvalidCommandHistory, validation.errors.to_h.inspect if validation.failure?

          events.each_with_index.reduce(initial) do |state, (event, index)|
            state.apply(event, canonical_input_digest: canonical_input_digests[index])
          end
        end

        def absent?
          status == "absent"
        end

        def terminal?
          %w[succeeded rejected].include?(status)
        end

        def succeeded?
          status == "succeeded"
        end

        def rejected?
          status == "rejected"
        end

        def apply(event, canonical_input_digest: nil)
          attributes = case event
                       when Events::CommandRegisteredV1
                         {
                           command_id: event.command_id,
                           request_id: event.request_id,
                           tool_name: event.tool_name,
                           canonical_input_digest:,
                           status: "registered"
                         }
                       when Events::CommandSucceededV1
                         { status: "succeeded" }
                       when Events::CommandRejectedV1
                         {
                           status: "rejected",
                           rejection_code: event.code,
                           rejection_reason: event.reason,
                           rejection_retryable: event.retryable
                         }
                       when Events::CommandRejectedV2
                         {
                           status: "rejected",
                           rejection_code: event.error.code,
                           rejection_reason: event.error.message,
                           rejection_retryable: event.retryable
                         }
                       end

          self.class.new(to_h.merge(attributes))
        end
      end
    end
  end
end
