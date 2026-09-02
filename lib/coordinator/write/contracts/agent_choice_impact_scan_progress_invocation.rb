# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanProgressInvocation < Dry::Validation::Contract
      include ProcessStepCausation

      params do
        required(:invocation).value(Types.Instance(Coordinator::Write::AgentChoiceImpactScanProgressInvocation))
      end

      rule(:invocation) do
        command = value.command
        checkpoint = value.checkpoint_event

        unless command.expected_checkpoint == value.checkpoint_reference
          key.failure("checkpoint reference must match the command")
        end
        unless value.checkpoint_reference.event_id == checkpoint.id &&
               value.checkpoint_reference.type == checkpoint.type &&
               value.checkpoint_reference.stream_revision == checkpoint.stream_revision
          key.failure("checkpoint event envelope must match its exact reference")
        end
        unless checkpoint.stream&.context == "AgentGovernance" &&
               checkpoint.stream&.stream_name == "AgentChoiceImpactScan" &&
               checkpoint.stream&.stream_id == command.scan_id
          key.failure("checkpoint must belong to the target impact scan")
        end
        unless %w[AgentChoiceImpactScanStarted AgentChoiceImpactScanProgressed].include?(checkpoint.type)
          key.failure("checkpoint must be a running scan fact")
        end
        key.failure("impact scan actor must be the system policy") unless command.actor.kind == "system"
        unless process_step_matches?(value.caused_by, command_id: command.command_id)
          key.failure("causal parent must be the ProcessStep that allocated the progress command")
        end
      end
    end
  end
end
