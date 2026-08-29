# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ResourceLeaseExpiryEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ExpireResourceLease))
        required(:state).value(Types.Instance(Domain::ResourceLeases::State))
        required(:expired_at).filled(:string)
      end

      rule(:plan, :command, :state, :expired_at) do
        plan = values[:plan]
        command = values[:command]
        state = values[:state]
        event = plan.events.first
        expected_stream = StreamFactory.new.resource_lease(command.resource_id)

        valid = plan.writes.length == 1 &&
          plan.writes.first.stream == expected_stream &&
          event.is_a?(Events::ResourceLeaseExpiredV2) &&
          exact_expiration?(event:, state:, command:, expired_at: values[:expired_at])
        key(:plan).failure("must expire only the exact current lease observation") unless valid
      end

      private

      def exact_expiration?(event:, state:, command:, expired_at:)
        event.to_h == {
          lease_id: command.lease_id,
          lease_set_id: command.lease_set_id,
          resource_id: command.resource_id,
          resource_kind: state.resource_kind,
          resource_path: state.resource_path,
          policy_version: state.policy_version,
          mode: state.mode,
          change_set_id: state.change_set_id,
          work_item_id: state.work_item_id,
          attempt_id: state.attempt_id,
          agent_id: state.agent_id,
          repository_id: state.repository_id,
          object_format: state.object_format,
          base_commit_oid: state.base_commit_oid,
          base_blob_oid: state.base_blob_oid,
          fencing_token: command.fencing_token,
          acquired_at: state.acquired_at,
          renewed_at: state.renewed_at,
          expires_at: command.expected_expires_at,
          expired_at:
        }
      end
    end
  end
end
