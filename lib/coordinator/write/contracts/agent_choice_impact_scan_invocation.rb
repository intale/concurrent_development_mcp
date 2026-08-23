# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanInvocation < Dry::Validation::Contract
      params do
        required(:invocation).value(Types.Instance(Coordinator::Write::AgentChoiceImpactScanInvocation))
      end

      rule(:invocation) do
        command = value.command
        source = value.source_event

        key.failure("source reference must match the command") unless command.source_event == value.source_reference
        unless command.source_global_position == source.global_position
          key.failure("source global position must match the command")
        end
        unless value.source_reference.event_id == source.id &&
               value.source_reference.type == source.type &&
               value.source_reference.stream_revision == source.stream_revision
          key.failure("source event envelope must match its exact reference")
        end
        key.failure("impact scan actor must be the system policy") unless command.actor.kind == "system"
      end
    end
  end
end
