# frozen_string_literal: true

module Coordinator
  module Contracts
    class ReadinessInvocation < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(Coordinator::ReadinessInvocation))
      end

      rule(:invocation) do
        command = value.command
        source = value.source
        identity = command.decision_identity.document

        key.failure("source event ID must match the command") unless command.source_activation_event_id == source.reference.event_id
        if command.source_activation_revision != source.reference.stream_revision
          key.failure("source revision must match the command")
        end
        key.failure("source ChangeSet must match the command") unless command.change_set_id == source.payload.change_set_id
        key.failure("decision source must match the invocation") unless identity.source_event == source.reference
        key.failure("decision target must match the command") unless identity.target_work_item_id == command.work_item_id
        key.failure("decision policy must match the command") unless identity.policy_version == command.policy_version
        unless command.command_id == command.readiness_decision_id
          key.failure("command and readiness decision identities must match")
        end
      end
    end
  end
end
