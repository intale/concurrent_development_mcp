# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactAssessmentInvocation < Dry::Validation::Contract
      PARENT_TYPES = %w[
        AgentChoiceAccepted
        AgentChoiceImpactScanStarted
        AgentChoiceImpactScanProgressed
      ].freeze

      params do
        required(:invocation).value(Types.Instance(Coordinator::Write::AgentChoiceImpactAssessmentInvocation))
      end

      rule(:invocation) do
        invocation = value
        command = invocation.command
        parent = invocation.caused_by
        reference = invocation.caused_by_reference
        persisted = parent.stream && parent.stream_revision && parent.global_position
        exact = reference.event_id == parent.id &&
                reference.type == parent.type &&
                reference.stream_context == parent.stream&.context &&
                reference.stream_name == parent.stream&.stream_name &&
                reference.stream_id == parent.stream&.stream_id &&
                reference.stream_revision == parent.stream_revision

        key.failure("causal parent must be a persisted scan checkpoint or accepted Choice") unless persisted && PARENT_TYPES.include?(parent.type)
        key.failure("causal parent must match its exact reference") unless exact
        unless command.actor.kind == "system" && command.actor.id == "agent-choice-decision-impact"
          key.failure("impact assessment actor must be the system policy")
        end
      end
    end
  end
end
