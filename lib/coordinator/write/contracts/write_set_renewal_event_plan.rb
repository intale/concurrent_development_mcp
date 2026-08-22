# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class WriteSetRenewalEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::RenewLeaseSet))
        required(:attempt_state).value(Types.Instance(Domain::Attempts::State))
        required(:current_observations).array(Types.Instance(CurrentLeaseObservationV1))
        required(:renewed_at).filled(:string)
        required(:expires_at).filled(:string)
      end

      rule(:plan, :command, :attempt_state, :current_observations, :renewed_at, :expires_at) do
        plan = values[:plan]
        command = values[:command]
        attempt_state = values[:attempt_state]
        observations = values[:current_observations]
        renewals = plan.events.first(observations.length)
        write_set_renewal = plan.events.last
        expected_streams = observations.map do |observation|
          StreamFactory.new.resource_lease(observation.reference.resource_key_hash)
        end + [ StreamFactory.new.attempt(command.attempt_id) ]

        unless plan.writes.length == observations.length + 1 &&
               plan.writes.map(&:stream) == expected_streams &&
               renewals.all? { _1.is_a?(Events::ResourceLeaseRenewedV1) } &&
               write_set_renewal.is_a?(Events::WriteSetRenewedV1)
          key(:plan).failure("must contain ordered resource renewals followed by one Attempt set renewal")
          next
        end

        verify_resource_renewals(
          renewals:,
          observations:,
          attempt_state:,
          command:,
          renewed_at: values[:renewed_at],
          expires_at: values[:expires_at]
        )
        verify_write_set_renewal(
          renewal: write_set_renewal,
          attempt_state:,
          command:,
          renewed_at: values[:renewed_at],
          expires_at: values[:expires_at]
        )
      end

      private

      def verify_resource_renewals(renewals:, observations:, attempt_state:, command:, renewed_at:, expires_at:)
        snapshot = attempt_state.base_snapshots.first
        valid = renewals.each_with_index.all? do |event, index|
          reference = observations.fetch(index).reference
          event.lease_id == reference.lease_id &&
            event.lease_set_id == command.lease_set_id &&
            event.resource_key == reference.resource_key &&
            event.resource_key_hash == reference.resource_key_hash &&
            event.resource_kind == reference.resource_kind &&
            event.resource_path == reference.resource_path &&
            event.base_blob_oid == reference.base_blob_oid &&
            event.change_set_id == command.change_set_id &&
            event.work_item_id == command.work_item_id &&
            event.attempt_id == command.attempt_id &&
            event.agent_id == command.actor.id &&
            event.repository_id == attempt_state.lease_repository_id &&
            event.object_format == snapshot.object_format &&
            event.base_commit_oid == snapshot.commit_oid &&
            event.fencing_token == reference.fencing_token &&
            event.renewed_at == renewed_at &&
            event.previous_expires_at == attempt_state.lease_expires_at &&
            event.expires_at == expires_at
        end
        key(:plan).failure("must preserve every current lease identity/token and only extend its common deadline") unless valid
      end

      def verify_write_set_renewal(renewal:, attempt_state:, command:, renewed_at:, expires_at:)
        valid = renewal.lease_set_id == command.lease_set_id &&
          renewal.change_set_id == command.change_set_id &&
          renewal.work_item_id == command.work_item_id &&
          renewal.attempt_id == command.attempt_id &&
          renewal.repository_id == attempt_state.lease_repository_id &&
          renewal.policy_version == attempt_state.lease_policy_version &&
          renewal.resources == attempt_state.lease_resources &&
          renewal.resource_count == attempt_state.lease_resources.length &&
          renewal.renewed_at == renewed_at &&
          renewal.previous_expires_at == attempt_state.lease_expires_at &&
          renewal.expires_at == expires_at
        key(:plan).failure("must summarize the unchanged complete set and its strict deadline extension") unless valid
      end
    end
  end
end
